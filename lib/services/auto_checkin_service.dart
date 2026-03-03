import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geofence_service/geofence_service.dart'
    hide LocationPermission, LocationAccuracy;
import '../data/models/attendance_log.dart';
import '../presentation/providers/providers.dart';
import '../logic/stats_calculator.dart';
import '../services/notification_service.dart';
import '../services/logger_service.dart';

class AutoCheckInService {
  static const bool _allowMockLocations = false; // Set to false for production
  final Ref ref;
  final GeofenceService _geofenceService = GeofenceService.instance;
  bool _isInitialized = false;

  AutoCheckInService(this.ref);

  Future<void> _logBackgroundEvent(String message) async {
    // The globally available logger handles trimming, persisting, and printing
    LoggerService.instance.background(message);
  }

  Future<void> initGeofence() async {
    if (_isInitialized) return;
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    final profileStream = ref
        .read(authServiceProvider)
        .getUserProfile(user.uid);
    final profile = await profileStream.first;

    if (profile == null ||
        profile.officeLat == null ||
        profile.officeLng == null) {
      await _logBackgroundEvent(
        'Geofence: Skipping init, no profile or location.',
      );
      return;
    }

    final geofence = Geofence(
      id: 'office_geofence',
      latitude: profile.officeLat!,
      longitude: profile.officeLng!,
      radius: [GeofenceRadius(id: 'radius_200m', length: 200)],
    );

    _geofenceService.setup(
      interval: 5000,
      accuracy: 100,
      loiteringDelayMs: 300000, // 5 minutes
      statusChangeDelayMs: 10000, // 10 seconds
      useActivityRecognition: false, // disabled as permission was removed
      allowMockLocations: _allowMockLocations,
      printDevLog: true,
      geofenceRadiusSortType: GeofenceRadiusSortType.DESC,
    );

    _geofenceService.addGeofenceStatusChangeListener(_onGeofenceStatusChanged);
    _geofenceService.addLocationChangeListener(_onLocationChanged);
    _geofenceService.addLocationServicesStatusChangeListener(
      _onLocationServicesStatusChanged,
    );
    _geofenceService.addStreamErrorListener(_onError);

    await _geofenceService.start([geofence]).catchError((e) {
      _logBackgroundEvent('Geofence: Error starting service: $e');
    });

    _isInitialized = true;
    await _logBackgroundEvent(
      'Geofence: Service initialized for office at ${profile.officeLat}, ${profile.officeLng}',
    );
  }

  Future<void> _onGeofenceStatusChanged(
    Geofence geofence,
    GeofenceRadius geofenceRadius,
    GeofenceStatus geofenceStatus,
    Location location,
  ) async {
    LoggerService.instance.background(
      'Geofence: Status changed: ${geofenceStatus.name}',
    );
    await _logBackgroundEvent('Geofence: Triggered ${geofenceStatus.name}');

    if (geofenceStatus == GeofenceStatus.ENTER ||
        geofenceStatus == GeofenceStatus.DWELL) {
      await _logBackgroundEvent(
        'Geofence: Entering/Dwelling in office area, checking attendance.',
      );
      await checkAndLogAttendance();
    } else if (geofenceStatus == GeofenceStatus.EXIT) {
      await _logBackgroundEvent(
        'Geofence: Exiting office area, attempting check-out.',
      );
      await checkAndLogOutAttendance();
    }
  }

  void _onLocationChanged(Location location) {
    LoggerService.instance.background(
      'Geofence: Location changed: ${location.latitude}, ${location.longitude}',
    );
  }

  void _onLocationServicesStatusChanged(bool status) {
    _logBackgroundEvent('Geofence: Location service status changed: $status');
  }

  void _onError(error) {
    _logBackgroundEvent('Geofence: Service error: $error');
  }

  Future<void> checkAndLogAttendance() async {
    try {
      final user = ref.read(currentUserProvider);
      if (user == null) {
        await _logBackgroundEvent('AutoCheckIn: No user logged in.');
        return;
      }

      final today = DateTime.now();

      // 1. Workday-Only Check
      if (today.weekday == DateTime.saturday ||
          today.weekday == DateTime.sunday) {
        LoggerService.instance.background('AutoCheckIn: Weekend, skipping.');
        return;
      }

      // 2. Time-of-Day Window (6:00 AM to 6:00 PM)
      if (today.hour < 6 || today.hour >= 18) {
        LoggerService.instance.background(
          'AutoCheckIn: Outside time window (6am-6pm), skipping.',
        );
        return;
      }

      final attendanceService = ref.read(attendanceServiceProvider);
      if (attendanceService == null) return;

      final logsStream = attendanceService.getAttendanceStream(today);
      final logs = await logsStream.first;
      final isLogged = logs.any(
        (log) => StatsCalculator.isSameDay(log.date, today),
      );

      // 4. Ensure Geofence Engine is Active
      if (!_isInitialized) {
        await initGeofence();
      }

      // Fetch profile directly
      final profileStream = ref
          .read(authServiceProvider)
          .getUserProfile(user.uid);
      final profile = await profileStream.first;

      if (profile == null ||
          profile.officeLat == null ||
          profile.officeLng == null) {
        return;
      }

      // Check permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        await _logBackgroundEvent('AutoCheckIn: Permission denied.');
        return;
      }

      // Robust Background Location Fetching
      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 15),
          ),
        );
      } catch (e) {
        LoggerService.instance.error(
          'AutoCheckIn: Failed precise location, trying last known: $e',
        );
        position = await Geolocator.getLastKnownPosition();
      }

      if (position == null) {
        LoggerService.instance.background(
          'AutoCheckIn: Could not determine location.',
        );
        await _logBackgroundEvent('AutoCheckIn: Could not determine location.');
        return;
      }

      double distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        profile.officeLat!,
        profile.officeLng!,
      );

      LoggerService.instance.background(
        'AutoCheckIn: Distance to office is $distance meters',
      );
      await _logBackgroundEvent(
        'AutoCheckIn: Distance is ${distance.toInt()}m',
      );

      // Threshold: 200 meters
      if (distance <= 200) {
        if (!isLogged) {
          final log = AttendanceLog(
            id: '${user.uid}_${today.millisecondsSinceEpoch}',
            userId: user.uid,
            date: today,
            timestamp: today,
            method: 'auto',
            inTime: today,
          );
          await attendanceService.logAttendance(log);
          await refreshSmartNotifications(ref);
          await NotificationService.showNotification(
            'Auto Check-in',
            'You have been checked in!',
          );
          await _logBackgroundEvent(
            'AutoCheckIn: SUCCESS - Checked in via background.',
          );
        } else {
          // If already logged today, check if they were checked-out previously and returned.
          final todayLogs = logs
              .where((log) => StatsCalculator.isSameDay(log.date, today))
              .toList();

          if (todayLogs.isNotEmpty) {
            final todayLog = todayLogs.first;
            // If they have an outTime but they are back at the office, we should
            // clear the outTime and effectively "re-check" them in
            if (todayLog.outTime != null) {
              final updatedLog = AttendanceLog(
                id: todayLog.id,
                userId: todayLog.userId,
                date: todayLog.date,
                timestamp: todayLog.timestamp,
                isSynced: todayLog.isSynced,
                method: todayLog.method,
                inTime: todayLog.inTime,
                outTime: null, // CLEAR outTime
              );

              await attendanceService.updateAttendance(updatedLog);
              LoggerService.instance.background(
                'AutoCheckIn: Returned to office. Cleared previous check-out time.',
              );
              await _logBackgroundEvent(
                'AutoCheckIn: SUCCESS - Re-entered office, checkout cleared.',
              );

              await NotificationService.showNotification(
                'Welcome Back',
                'Your check-out time has been paused since you returned.',
              );
            } else {
              LoggerService.instance.background(
                'AutoCheckIn: Already logged today (and nearby).',
              );
            }
          }
        }
      } else {
        if (isLogged) {
          LoggerService.instance.background(
            'AutoCheckIn: Far from office, attempting check-out.',
          );
          await checkAndLogOutAttendance();
        }
      }
    } catch (e, stack) {
      LoggerService.instance.error('AutoCheckIn error: $e\n$stack');
      await _logBackgroundEvent('AutoCheckIn ERROR: $e');
    }
  }

  Future<void> checkAndLogOutAttendance() async {
    try {
      final user = ref.read(currentUserProvider);
      if (user == null) {
        await _logBackgroundEvent('AutoCheckOut: No user logged in.');
        return;
      }

      final today = DateTime.now();
      final attendanceService = ref.read(attendanceServiceProvider);
      if (attendanceService == null) return;

      final logsStream = attendanceService.getAttendanceStream(today);
      final logs = await logsStream.first;

      final todayLogs = logs
          .where((log) => StatsCalculator.isSameDay(log.date, today))
          .toList();

      if (todayLogs.isEmpty) {
        LoggerService.instance.background(
          'AutoCheckOut: No attendance logged today, skipping.',
        );
        return;
      }

      final todayLog = todayLogs.first;

      // Always update the out time to the most recent departure event.
      // This way if a user leaves the office at 3pm, and geo-triggers again at 4pm,
      // the latest time acts as their updated outTime unless they re-entered.
      final updatedLog = AttendanceLog(
        id: todayLog.id,
        userId: todayLog.userId,
        date: todayLog.date,
        timestamp: todayLog.timestamp,
        isSynced: todayLog.isSynced,
        method: todayLog.method,
        inTime: todayLog.inTime,
        outTime: today,
      );

      await attendanceService.updateAttendance(updatedLog);

      // We only want to notify the user of the VERY FIRST checkout
      // so we don't spam notifications every 15m they are away from office.
      if (todayLog.outTime == null) {
        await refreshSmartNotifications(ref);
        await NotificationService.showNotification(
          'Auto Check-out',
          'You have been checked out!',
        );
        await _logBackgroundEvent(
          'AutoCheckOut: SUCCESS - First checkout of the day.',
        );
      } else {
        await _logBackgroundEvent(
          'AutoCheckOut: SUCCESS - Updated existing checkout time.',
        );
      }
    } catch (e, stack) {
      LoggerService.instance.error('AutoCheckOut error: $e\n$stack');
      await _logBackgroundEvent('AutoCheckOut ERROR: $e');
    }
  }
}

final autoCheckInServiceProvider = Provider<AutoCheckInService>(
  (ref) => AutoCheckInService(ref),
);
