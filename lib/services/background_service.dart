import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:native_geofence/native_geofence.dart';
import 'package:workmanager/workmanager.dart';

import '../presentation/providers/providers.dart';
import 'attendance_detection/confirmation_scheduler.dart';
import 'auto_checkin_service.dart';
import 'notification_service.dart';
import 'logger_service.dart';
import 'attendance_service.dart';

/// Bootstraps the minimal set of services a background isolate needs before
/// touching [autoCheckInServiceProvider] — shared by every background entry
/// point (`geofenceTriggered`, [attendanceConfirmationCallbackDispatcher]).
/// Neither Flutter nor Riverpod's async providers can be assumed alive in
/// a freshly-spawned background isolate, so this re-initializes from
/// scratch every time, exactly like the pre-existing `geofenceTriggered`
/// always did.
Future<ProviderContainer> _bootstrapBackgroundContainer() async {
  await Hive.initFlutter();
  await Firebase.initializeApp();
  AttendanceService.initializeSettings();
  await NotificationService.init();

  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
}

@pragma('vm:entry-point')
Future<void> geofenceTriggered(GeofenceCallbackParams params) async {
  print('NATIVE_GEOFENCE_ISOLATE: CALLBACK INVOKED BY OS');
  WidgetsFlutterBinding.ensureInitialized();
  // Raw print for OS level verification
  print('NATIVE_GEOFENCE_ISOLATE: Received event=${params.event.name}');

  try {
    final container = await _bootstrapBackgroundContainer();
    print('NATIVE_GEOFENCE_ISOLATE: Core services initialized.');

    // Skip waiting for Riverpod async providers in background isolate.
    // AutoCheckInService uses direct FirebaseAuth.instance.currentUser fallback.
    final autoCheckInService = container.read(autoCheckInServiceProvider);

    // Every geofence transition (enter/exit/dwell) is only ever a *signal*
    // into the detection engine now — never a direct check-in/check-out.
    // See docs/AUTO_ATTENDANCE_DESIGN.md.
    await autoCheckInService.handleGeofenceEvent(params.event);

    print('NATIVE_GEOFENCE_ISOLATE: GeofenceTriggered: Handle complete.');
    container.dispose();
  } catch (e, stack) {
    print('NATIVE_GEOFENCE_ISOLATE CRITICAL ERROR: $e\n$stack');
    try {
      await Hive.initFlutter();
      print(
        'GeofenceTriggered ERROR written to console implicitly: $e\n$stack',
      );
    } catch (_) {}
  }
}

/// Workmanager entry point for the detection engine's deferred "confirming
/// sample" re-check (see [ConfirmationScheduler] and
/// docs/AUTO_ATTENDANCE_DESIGN.md section 6.2). This is what lets an
/// in-progress episode resolve on its own when no further geofence event or
/// app-foreground check happens to arrive naturally — without it, an
/// episode with only one supporting sample would sit unresolved forever.
///
/// Reuses exactly the same foreground-check code path a user opening the
/// app already triggers (`checkAndLogAttendance`) — this scheduled wake-up
/// is simply a way to get that same evaluation to run without the user
/// having to open the app.
@pragma('vm:entry-point')
void attendanceConfirmationCallbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    if (taskName != attendanceConfirmationTaskName) return true;
    try {
      final container = await _bootstrapBackgroundContainer();
      await container.read(autoCheckInServiceProvider).checkAndLogAttendance();
      container.dispose();
      return true;
    } catch (e, stack) {
      LoggerService.instance.error(
        'AttendanceConfirmation: CRITICAL error: $e\n$stack',
      );
      // Returning false tells Android WorkManager to retry per its backoff
      // policy; iOS ignores the return value (see BackgroundTaskHandler docs).
      return false;
    }
  });
}

class BackgroundService {
  static Future<void> init(ProviderContainer container) async {
    try {
      await NativeGeofenceManager.instance.initialize();
      await container.read(autoCheckInServiceProvider).initGeofence();
    } catch (e) {
      LoggerService.instance.error(
        'BackgroundService: Failed to init geofence runtime: $e',
      );
    }

    try {
      await Workmanager().initialize(attendanceConfirmationCallbackDispatcher);
    } catch (e) {
      LoggerService.instance.error(
        'BackgroundService: Failed to init Workmanager: $e',
      );
    }
  }

  static Future<void> checkAndRegisterTask() async {
    // No-op for backwards compatibility during refactor, Native Geofencing handles persistence via OS.
  }
}
