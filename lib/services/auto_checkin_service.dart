import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geofence_service/geofence_service.dart'
    hide LocationPermission, LocationAccuracy;
import 'package:hive_flutter/hive_flutter.dart';
import 'dart:developer' as developer;
import '../data/models/attendance_log.dart';
import '../presentation/providers/providers.dart';
import '../logic/stats_calculator.dart';
import '../services/notification_service.dart';

class AutoCheckInService {
  static const bool _allowMockLocations = false; // Set to false for production
  final Ref ref;
  final GeofenceService _geofenceService = GeofenceService.instance;
  bool _isInitialized = false;

  AutoCheckInService(this.ref);

  Future<void> _logBackgroundEvent(String message) async {
    try {
      final box = await Hive.openBox<String>('background_logs');
      final timestamp = DateTime.now().toIso8601String();
      await box.add('[$timestamp] $message');
      if (box.length > 100) await box.deleteAt(0);
    } catch (e) {
      developer.log('Failed to write to Hive log: $e');
    }
  }

  Future<void> _stopGeofenceService() async {
    try {
      await _geofenceService.stop();
      _isInitialized = false;
      await _logBackgroundEvent(
        'Geofence: Service stopped (condition met, saving battery).',
      );
    } catch (e) {
      developer.log('Failed to stop geofence service: $e');
    }
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
    developer.log('Geofence: Status changed: ${geofenceStatus.name}');
    await _logBackgroundEvent('Geofence: Triggered ${geofenceStatus.name}');

    if (geofenceStatus == GeofenceStatus.ENTER ||
        geofenceStatus == GeofenceStatus.DWELL) {
      await _logBackgroundEvent(
        'Geofence: Entering/Dwelling in office area, checking attendance.',
      );
      await checkAndLogAttendance();
    }
  }

  void _onLocationChanged(Location location) {
    developer.log(
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
        developer.log('AutoCheckIn: Weekend, skipping check-in.');
        await _stopGeofenceService();
        return;
      }

      // 2. Time-of-Day Window (6:00 AM to 6:00 PM)
      if (today.hour < 6 || today.hour >= 18) {
        developer.log('AutoCheckIn: Outside time window (6am-6pm), skipping.');
        return;
      }

      // 3. Already Checked-In Short-Circuit
      final attendanceService = ref.read(attendanceServiceProvider);
      if (attendanceService == null) return;

      final logsStream = attendanceService.getAttendanceStream(today);
      final logs = await logsStream.first;
      final isLogged = logs.any(
        (log) => StatsCalculator.isSameDay(log.date, today),
      );

      if (isLogged) {
        developer.log('AutoCheckIn: Already logged today, skipping.');
        await _stopGeofenceService();
        return;
      }

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
        developer.log(
          'AutoCheckIn: Failed precise location, trying last known: $e',
        );
        position = await Geolocator.getLastKnownPosition();
      }

      if (position == null) {
        developer.log('AutoCheckIn: Could not determine location.');
        await _logBackgroundEvent('AutoCheckIn: Could not determine location.');
        return;
      }

      double distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        profile.officeLat!,
        profile.officeLng!,
      );

      developer.log('AutoCheckIn: Distance to office is $distance meters');
      await _logBackgroundEvent(
        'AutoCheckIn: Distance is ${distance.toInt()}m',
      );

      // Threshold: 200 meters
      if (distance <= 200) {
        final log = AttendanceLog(
          id: '${user.uid}_${today.millisecondsSinceEpoch}',
          userId: user.uid,
          date: today,
          timestamp: today,
          method: 'auto',
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
      }
    } catch (e, stack) {
      developer.log('AutoCheckIn error: $e\n$stack');
      await _logBackgroundEvent('AutoCheckIn ERROR: $e');
    }
  }
}

final autoCheckInServiceProvider = Provider<AutoCheckInService>(
  (ref) => AutoCheckInService(ref),
);
