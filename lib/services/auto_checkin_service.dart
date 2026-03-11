import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:native_geofence/native_geofence.dart';
import '../data/models/attendance_log.dart';
import '../presentation/providers/providers.dart';
import '../logic/stats_calculator.dart';
import '../services/notification_service.dart';
import '../services/logger_service.dart';
import '../services/background_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'attendance_service.dart';
import 'admin_service.dart';

class AutoCheckInService {
  final Ref ref;
  bool _isInitialized = false;

  AutoCheckInService(this.ref);

  Future<void> _logBackgroundEvent(String message) async {
    // Avoid LoggerService in background isolate if it causes hangs
    // Using debugPrint to satisfy avoid_print lint while maintaining console output for debugging geofence
    debugPrint('BACKGROUND_EVENT: $message');
  }

  Future<void> initGeofence() async {
    // We allow re-initialization to update radius
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

    final Geofence geofence = Geofence(
      id: 'office_geofence',
      location: Location(
        latitude: profile.officeLat!,
        longitude: profile.officeLng!,
      ),
      radiusMeters: ref.read(geofenceRadiusProvider).toDouble(),
      triggers: {GeofenceEvent.enter, GeofenceEvent.exit, GeofenceEvent.dwell},
      androidSettings: AndroidGeofenceSettings(
        initialTriggers: {GeofenceEvent.enter, GeofenceEvent.dwell},
        expiration: const Duration(days: 9999),
        loiteringDelay: const Duration(seconds: 10),
        notificationResponsiveness: const Duration(
          seconds: 0,
        ), // Max responsiveness
      ),
      iosSettings: IosGeofenceSettings(initialTrigger: true),
    );

    try {
      await _logBackgroundEvent(
        'Geofence: Initializing NativeGeofenceManager...',
      );
      await NativeGeofenceManager.instance.initialize();

      await _logBackgroundEvent(
        'Geofence: Creating geofence "office_geofence" at '
        '${profile.officeLat}, ${profile.officeLng} with radius ${geofence.radiusMeters}m',
      );

      await NativeGeofenceManager.instance.createGeofence(
        geofence,
        geofenceTriggered,
      );

      _isInitialized = true;
      await _logBackgroundEvent(
        'Geofence: SUCCESS - Service initialized and geofence registered.',
      );

      // Check already registered geofences for verification
      final registered = await NativeGeofenceManager.instance
          .getRegisteredGeofences();
      await _logBackgroundEvent(
        'Geofence: Currently registered count: ${registered.length}',
      );
      for (var g in registered) {
        await _logBackgroundEvent('Geofence: Registered ID: ${g.id}');
      }
    } catch (e, stack) {
      _logBackgroundEvent('Geofence: ERROR during initialization: $e\n$stack');
    }
  }

  // Listener methods removed as `native_geofence` uses a top-level global callback `@pragma('vm:entry-point')` defined in background_service.dart

  Future<void> checkAndLogAttendance() async {
    try {
      await _logBackgroundEvent(
        'AutoCheckIn: checkAndLogAttendance triggered.',
      );
      await _logBackgroundEvent('AutoCheckIn: Checking user state...');
      var user = ref.read(currentUserProvider);

      // Fallback for background isolate if provider hasn't filled yet
      if (user == null) {
        await _logBackgroundEvent(
          'AutoCheckIn: currentUserProvider null, trying direct FirebaseAuth...',
        );
        user = FirebaseAuth.instance.currentUser;
      }

      if (user == null) {
        await _logBackgroundEvent(
          'AutoCheckIn: FAILED: No user found (Isolate).',
        );
        await _logBackgroundEvent('AutoCheckIn: No user logged in.');
        return;
      } else {
        await _logBackgroundEvent('AutoCheckIn: User found: ${user.uid}');
      }

      bool allowMockLocation = false;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.reload();
        allowMockLocation = prefs.getBool('allowMockLocation') ?? false;
      } catch (_) {}

      final config = ref.read(globalConfigProvider).value ?? {};
      if (config.containsKey('allowMockLocation')) {
        allowMockLocation = config['allowMockLocation'] == true;
      }

      final today = DateTime.now();

      // Ensure Geofence Engine is Active
      if (!_isInitialized) {
        await initGeofence();
      }

      // Fetch profile directly with a timeout
      final profile = await ref
          .read(authServiceProvider)
          .getUserProfile(user.uid)
          .first
          .timeout(
            const Duration(seconds: 3),
            onTimeout: () {
              return null;
            },
          );

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
            timeLimit: Duration(seconds: 3),
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

      // Mock Location Check
      if (position.isMocked && !allowMockLocation) {
        LoggerService.instance.background(
          'AutoCheckIn: Mock location detected and disallowed.',
        );
        await _logBackgroundEvent(
          'AutoCheckIn: Blocked - Mock Location detected.',
        );
        return;
      }

      double distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        profile.officeLat!,
        profile.officeLng!,
      );

      final radius = ref.read(geofenceRadiusProvider).toDouble();
      final checkInThreshold = radius;
      final checkOutThreshold = radius;

      await _logBackgroundEvent(
        'AutoCheckIn: Distance is ${distance.toInt()}m',
      );

      // Use manual service instantiation instead of provider to avoid nulls in background isolate
      final attendanceService = AttendanceService(user.uid);
      final logs = await attendanceService.getAttendanceForDate(today);
      final isLoggedToday = logs.any(
        (log) => StatsCalculator.isSameDay(log.date, today),
      );

      // --- LOGIC SPLIT: CHECK-IN vs CHECK-OUT ---

      if (distance <= checkInThreshold ||
          (allowMockLocation && distance <= checkInThreshold)) {
        // --- ATTEMPT CHECK-IN ---
        if (!isLoggedToday) {
          // 1. Workday-Only Check (Bypassed if allowMockLocation is true)
          if (!allowMockLocation) {
            if (today.weekday == DateTime.saturday ||
                today.weekday == DateTime.sunday) {
              await _logBackgroundEvent(
                'AutoCheckIn: Skipping Check-in - Weekend.',
              );
              return;
            }

            // 2. Time-of-Day Window (6:00 AM to 6:00 PM) for NEW check-ins
            if (today.hour < 6 || today.hour >= 18) {
              await _logBackgroundEvent(
                'AutoCheckIn: Skipping Check-in - Outside 6am-6pm.',
              );
              return;
            }
          }

          final log = AttendanceLog(
            id: '${user.uid}_${today.year}-${today.month}-${today.day}',
            userId: user.uid,
            date: today,
            timestamp: today,
            method: 'auto',
            sessions: [AttendanceSession(inTime: today)],
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
            final sessions = List<AttendanceSession>.from(todayLog.sessions);
            if (sessions.isNotEmpty && sessions.last.outTime != null) {
              // Create a brand new active session for this return visit
              sessions.add(AttendanceSession(inTime: today));

              final updatedLog = AttendanceLog(
                id: todayLog.id,
                userId: todayLog.userId,
                date: todayLog.date,
                timestamp: todayLog.timestamp,
                isSynced: todayLog.isSynced,
                method: todayLog.method,
                sessions: sessions,
              );

              await attendanceService.updateAttendance(updatedLog);
              await NotificationService.showNotification(
                'Welcome Back',
                'Your check-out time has been paused since you returned.',
              );
              await _logBackgroundEvent(
                'AutoCheckIn: SUCCESS - Re-entered office, session resumed.',
              );
            }
          }
        }
      } else if (distance > checkOutThreshold) {
        // --- ATTEMPT CHECK-OUT ---
        // We ALWAYS allow check-outs if distance > 200m and user is logged in, regardless of time.
        if (isLoggedToday) {
          await checkAndLogOutAttendance();
        }
      }
    } catch (e, stack) {
      await _logBackgroundEvent('AutoCheckIn: CRITICAL error: $e\n$stack');
    }
  }

  Future<void> checkAndLogOutAttendance() async {
    try {
      await _logBackgroundEvent(
        'AutoCheckIn: checkAndLogOutAttendance triggered.',
      );
      await _logBackgroundEvent('AutoCheckOut: Checking user state...');
      var user = ref.read(currentUserProvider);

      // Fallback for background isolate if provider hasn't filled yet
      if (user == null) {
        await _logBackgroundEvent(
          'AutoCheckOut: currentUserProvider null, trying direct FirebaseAuth...',
        );
        user = FirebaseAuth.instance.currentUser;
      }

      if (user == null) {
        await _logBackgroundEvent(
          'AutoCheckOut: FAILED: No user found (Isolate).',
        );
        await _logBackgroundEvent('AutoCheckOut: No user logged in.');
        return;
      }

      await _logBackgroundEvent('AutoCheckOut: User found: ${user.uid}');

      final today = DateTime.now();

      // Use manual service instantiation instead of provider to avoid nulls in background isolate
      final attendanceService = AttendanceService(user.uid);
      final logs = await attendanceService.getAttendanceForDate(today);

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

      final sessions = List<AttendanceSession>.from(todayLog.sessions);

      // Update the active session's outTime
      bool newlyCheckedOut = false;
      if (sessions.isNotEmpty && sessions.last.outTime == null) {
        sessions[sessions.length - 1] = AttendanceSession(
          inTime: sessions.last.inTime,
          outTime: today,
        );
        newlyCheckedOut = true;
      } else if (sessions.isNotEmpty) {
        // If they trigger an exit but their last session was already checked out (e.g. dwell triggers),
        // we just update the outTime of the last session to extend it.
        sessions[sessions.length - 1] = AttendanceSession(
          inTime: sessions.last.inTime,
          outTime: today,
        );
      }

      final updatedLog = AttendanceLog(
        id: todayLog.id,
        userId: todayLog.userId,
        date: todayLog.date,
        timestamp: todayLog.timestamp,
        isSynced: todayLog.isSynced,
        method: todayLog.method,
        sessions: sessions,
      );

      await attendanceService.updateAttendance(updatedLog);

      if (newlyCheckedOut) {
        await refreshSmartNotifications(ref);
        await NotificationService.showNotification(
          'Auto Check-out',
          'You have been checked out!',
        );
        await _logBackgroundEvent(
          'AutoCheckOut: SUCCESS - New checkout session.',
        );
      } else {
        await _logBackgroundEvent(
          'AutoCheckOut: SUCCESS - Updated existing checkout time.',
        );
      }
    } catch (e, stack) {
      await _logBackgroundEvent('AutoCheckOut: CRITICAL error: $e\n$stack');
    }
  }

  Future<void> stopGeofence() async {
    try {
      await NativeGeofenceManager.instance.removeGeofenceById(
        'office_geofence',
      );
      _isInitialized = false;
      await _logBackgroundEvent('Geofence: Stopped and removed.');
    } catch (e, stack) {
      _logBackgroundEvent('Geofence: ERROR during stopping: $e\n$stack');
    }
  }
}

final autoCheckInServiceProvider = Provider<AutoCheckInService>(
  (ref) => AutoCheckInService(ref),
);
