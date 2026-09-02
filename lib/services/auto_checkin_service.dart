import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:native_geofence/native_geofence.dart';
import '../data/models/attendance_log.dart';
import '../presentation/providers/providers.dart';
import '../logic/stats_calculator.dart';
import 'attendance_detection/attendance_detection_engine.dart';
import 'attendance_detection/detection_models.dart';
import 'attendance_detection/signal_sources/activity_signal_source.dart';
import 'attendance_detection/signal_sources/network_signal_source.dart';
import '../services/notification_service.dart';
import '../services/logger_service.dart';
import '../services/background_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'attendance_service.dart';
import 'admin_service.dart';

/// Orchestrates automatic attendance: registers the low-power OS geofence,
/// feeds every geofence transition / foreground check into the shared
/// [AttendanceDetectionEngine], and turns the engine's (rare) automatic
/// decisions into Firestore-backed [AttendanceLog] writes.
///
/// This class owns exactly the business rules that pre-date the detection
/// redesign (working-day gate, 6am-6pm new-check-in window, the
/// "capture check-in/out times" toggle, multi-session resume) — see
/// docs/AUTO_ATTENDANCE_DESIGN.md section 11. Everything about *whether* an
/// arrival/departure is credible now lives in `attendance_detection/`.
class AutoCheckInService {
  final Ref ref;
  bool _isInitialized = false;

  late final AttendanceDetectionEngine _engine = AttendanceDetectionEngine(
    activitySource: PluginActivitySignalSource(),
    networkSource: WifiNetworkSignalSource(
      workplaceSsidProvider: () => ref.read(workplaceWifiSsidProvider),
    ),
  );

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
      // `dwell` is registered for Android, where GeofencingClient supports it
      // natively at effectively zero extra battery cost. iOS has no native
      // dwell concept (CLRegion monitoring only offers enter/exit) — the
      // detection engine computes an equivalent "soft dwell" itself from
      // enter/exit timestamps, so it does not depend on this trigger firing
      // on iOS. See docs/AUTO_ATTENDANCE_DESIGN.md sections 2 and 10.
      triggers: {GeofenceEvent.enter, GeofenceEvent.exit, GeofenceEvent.dwell},
      androidSettings: AndroidGeofenceSettings(
        initialTriggers: {GeofenceEvent.enter, GeofenceEvent.dwell},
        expiration: const Duration(days: 9999),
        loiteringDelay: const Duration(minutes: 1),
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

  Future<bool> _resolveAllowMockLocation() async {
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
    return allowMockLocation;
  }

  /// Low-weight HistoricalEvidence tie-breaker (docs section 4): is `now`
  /// within 90 minutes of the user's recent median check-in/check-out
  /// time-of-day? Returns null (unavailable, never penalized) when there
  /// isn't enough recent history to be meaningful.
  bool? _historicalSupportsTime(
    List<AttendanceLog> recentLogs,
    DateTime now, {
    required bool arrival,
  }) {
    final minutesOfDay = <int>[];
    for (final log in recentLogs) {
      for (final session in log.sessions) {
        final t = arrival ? session.inTime : session.outTime;
        if (t != null) minutesOfDay.add(t.hour * 60 + t.minute);
      }
    }
    if (minutesOfDay.length < 3) return null;
    minutesOfDay.sort();
    final median = minutesOfDay[minutesOfDay.length ~/ 2];
    final nowMinutes = now.hour * 60 + now.minute;
    return (nowMinutes - median).abs() <= 90;
  }

  /// Foreground evaluation entry point — called on app resume/startup, and
  /// after granting permissions during onboarding. Method name/signature
  /// preserved from before the detection redesign so existing call sites
  /// (home screen, settings, onboarding) needed no changes.
  Future<void> checkAndLogAttendance() async {
    try {
      await _logBackgroundEvent('AutoCheckIn: foreground check triggered.');
      var user = ref.read(currentUserProvider);
      user ??= FirebaseAuth.instance.currentUser;
      if (user == null) {
        await _logBackgroundEvent('AutoCheckIn: No user logged in.');
        return;
      }

      if (!_isInitialized) {
        await initGeofence();
      }

      final profile = await ref
          .read(authServiceProvider)
          .getUserProfile(user.uid)
          .first
          .timeout(const Duration(seconds: 3), onTimeout: () => null);

      if (profile == null ||
          profile.officeLat == null ||
          profile.officeLng == null) {
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        await _logBackgroundEvent('AutoCheckIn: Permission denied.');
        return;
      }

      final decision = await _engine.processForegroundCheck(
        userId: user.uid,
        officeLat: profile.officeLat!,
        officeLng: profile.officeLng!,
        radiusMeters: ref.read(geofenceRadiusProvider).toDouble(),
        allowMockLocation: await _resolveAllowMockLocation(),
        historicalSupportsArrivalNow: await _historicalEvidence(
          user.uid,
          arrival: true,
        ),
        historicalSupportsDepartureNow: await _historicalEvidence(
          user.uid,
          arrival: false,
        ),
      );

      if (decision != null) await _applyDecision(user.uid, decision);
    } catch (e, stack) {
      await _logBackgroundEvent('AutoCheckIn: CRITICAL error: $e\n$stack');
    }
  }

  /// Geofence-transition entry point, called from the background isolate
  /// (`geofenceTriggered` in background_service.dart). Unlike the pre-redesign
  /// implementation, no geofence event is ever treated as a check-in/check-out
  /// on its own — it is only ever fed into the detection engine as a signal.
  Future<void> handleGeofenceEvent(GeofenceEvent event) async {
    try {
      await _logBackgroundEvent(
        'AutoCheckIn: geofence event ${event.name} received.',
      );
      var user = ref.read(currentUserProvider);
      user ??= FirebaseAuth.instance.currentUser;
      if (user == null) {
        await _logBackgroundEvent('AutoCheckIn: No user logged in.');
        return;
      }

      if (!_isInitialized) {
        await initGeofence();
      }

      final profile = await ref
          .read(authServiceProvider)
          .getUserProfile(user.uid)
          .first
          .timeout(const Duration(seconds: 3), onTimeout: () => null);

      if (profile == null ||
          profile.officeLat == null ||
          profile.officeLng == null) {
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        await _logBackgroundEvent('AutoCheckIn: Permission denied.');
        return;
      }

      final transition = switch (event) {
        GeofenceEvent.enter => GeofenceTransition.enter,
        GeofenceEvent.exit => GeofenceTransition.exit,
        GeofenceEvent.dwell => GeofenceTransition.dwell,
      };

      final decision = await _engine.processGeofenceEvent(
        userId: user.uid,
        transition: transition,
        officeLat: profile.officeLat!,
        officeLng: profile.officeLng!,
        radiusMeters: ref.read(geofenceRadiusProvider).toDouble(),
        allowMockLocation: await _resolveAllowMockLocation(),
        historicalSupportsArrivalNow: await _historicalEvidence(
          user.uid,
          arrival: true,
        ),
        historicalSupportsDepartureNow: await _historicalEvidence(
          user.uid,
          arrival: false,
        ),
      );

      if (decision != null) await _applyDecision(user.uid, decision);
    } catch (e, stack) {
      await _logBackgroundEvent('AutoCheckIn: CRITICAL error: $e\n$stack');
    }
  }

  Future<bool?> _historicalEvidence(String userId, {required bool arrival}) async {
    try {
      final attendanceService = AttendanceService(userId);
      final recent = await attendanceService.getRecentLogsFromCache();
      return _historicalSupportsTime(recent, DateTime.now(), arrival: arrival);
    } catch (_) {
      return null;
    }
  }

  Future<void> _applyDecision(String userId, AttendanceDecision decision) async {
    switch (decision.type) {
      case AttendanceDecisionType.checkIn:
        await _applyCheckIn(userId, decision);
      case AttendanceDecisionType.checkOut:
        await _applyCheckOut(userId, decision);
    }
  }

  Future<void> _applyCheckIn(String userId, AttendanceDecision decision) async {
    final today = DateTime.now();
    final attendanceService = AttendanceService(userId);
    final captureTimes = ref.read(captureCheckInOutProvider);

    final logs = await attendanceService.getAttendanceForDate(today);
    final todayLogs = logs
        .where((log) => StatsCalculator.isSameDay(log.date, today))
        .toList();

    final bool allowMockLocation = await _resolveAllowMockLocation();

    if (todayLogs.isEmpty) {
      // Brand new day: preserve the pre-existing working-day + time-of-day
      // gate for *new* check-ins (bypassed only when mock locations are
      // explicitly allowed, e.g. for QA).
      if (!allowMockLocation) {
        final workingWeekdays =
            ref.read(attendanceRulesConfigProvider).workingWeekdays;
        if (!workingWeekdays.contains(today.weekday)) {
          await _logBackgroundEvent(
            'AutoCheckIn: Skipping Check-in - Not a configured working day.',
          );
          return;
        }
        if (today.hour < 6 || today.hour >= 18) {
          await _logBackgroundEvent(
            'AutoCheckIn: Skipping Check-in - Outside 6am-6pm.',
          );
          return;
        }
      }

      final log = AttendanceLog(
        id: '${userId}_${today.year}-${today.month}-${today.day}',
        userId: userId,
        date: today,
        timestamp: today,
        method: 'auto',
        sessions: [
          AttendanceSession(
            inTime: decision.estimatedTimestamp,
            outTime: captureTimes ? null : decision.estimatedTimestamp,
            checkInMetadata: decision.toAttendanceMetadata(),
          ),
        ],
      );
      await attendanceService.logAttendance(log);
      await refreshSmartNotifications(ref);
      await NotificationService.showNotification(
        'Auto Check-in',
        'You have been checked in!',
      );
      await _logBackgroundEvent(
        'AutoCheckIn: SUCCESS - Checked in via background '
        '(confidence=${decision.confidence.toStringAsFixed(2)}).',
      );
      return;
    }

    if (!captureTimes) return; // Day already marked complete at check-in.

    // Resume: the day already has a log, and the engine just confirmed a
    // fresh arrival (i.e. the last session had already been checked out) —
    // start a brand new session for this return visit.
    final todayLog = todayLogs.first;
    final sessions = List<AttendanceSession>.from(todayLog.sessions);
    if (sessions.isEmpty || sessions.last.outTime == null) {
      // Nothing to resume — already an open session. Idempotency guard.
      return;
    }

    sessions.add(
      AttendanceSession(
        inTime: decision.estimatedTimestamp,
        checkInMetadata: decision.toAttendanceMetadata(),
      ),
    );

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

  Future<void> _applyCheckOut(String userId, AttendanceDecision decision) async {
    if (!ref.read(captureCheckInOutProvider)) {
      await _logBackgroundEvent(
        'AutoCheckOut: Skipped - times are not being captured.',
      );
      return;
    }

    final today = DateTime.now();
    final attendanceService = AttendanceService(userId);
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

    if (sessions.isEmpty || sessions.last.outTime != null) {
      // Idempotency guard: the detection engine's own state machine should
      // never emit a second check-out for the same open session, but this
      // defends against a duplicate/replayed decision regardless.
      await _logBackgroundEvent(
        'AutoCheckOut: Skipped - no open session to close.',
      );
      return;
    }

    sessions[sessions.length - 1] = sessions.last.copyWith(
      outTime: decision.estimatedTimestamp,
      checkOutMetadata: decision.toAttendanceMetadata(),
    );

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
    await refreshSmartNotifications(ref);
    await NotificationService.showNotification(
      'Auto Check-out',
      'You have been checked out!',
    );
    await _logBackgroundEvent(
      'AutoCheckOut: SUCCESS - checked out '
      '(confidence=${decision.confidence.toStringAsFixed(2)}).',
    );
  }

  Future<void> stopGeofence() async {
    try {
      await NativeGeofenceManager.instance.removeGeofenceById(
        'office_geofence',
      );
      _isInitialized = false;
      final user = ref.read(currentUserProvider);
      if (user != null) await _engine.reset(user.uid);
      await _logBackgroundEvent('Geofence: Stopped and removed.');
    } catch (e, stack) {
      _logBackgroundEvent('Geofence: ERROR during stopping: $e\n$stack');
    }
  }
}

final autoCheckInServiceProvider = Provider<AutoCheckInService>(
  (ref) => AutoCheckInService(ref),
);
