import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:native_geofence/native_geofence.dart';

import '../presentation/providers/providers.dart';
import 'auto_checkin_service.dart';
import 'notification_service.dart';
import 'logger_service.dart';
import 'attendance_service.dart';

@pragma('vm:entry-point')
Future<void> geofenceTriggered(GeofenceCallbackParams params) async {
  print('NATIVE_GEOFENCE_ISOLATE: CALLBACK INVOKED BY OS');
  WidgetsFlutterBinding.ensureInitialized();
  // Raw print for OS level verification
  print('NATIVE_GEOFENCE_ISOLATE: Received event=${params.event.name}');

  try {
    // 1. Initialize Hive FIRST (required by LoggerService which is used by NotificationService)
    await Hive.initFlutter();

    // 2. Initialize necessary core services
    await Firebase.initializeApp();
    AttendanceService.initializeSettings();

    // 3. Initialize NotificationService (now safe because Hive is ready)
    await NotificationService.init();

    print('NATIVE_GEOFENCE_ISOLATE: Core services initialized.');

    final prefs = await SharedPreferences.getInstance();

    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );

    // Skip waiting for Riverpod async providers in background isolate.
    // AutoCheckInService uses direct FirebaseAuth.instance.currentUser fallback.

    final autoCheckInService = container.read(autoCheckInServiceProvider);

    if (params.event == GeofenceEvent.enter ||
        params.event == GeofenceEvent.dwell) {
      await autoCheckInService.checkAndLogAttendance();
    } else if (params.event == GeofenceEvent.exit) {
      await autoCheckInService.checkAndLogOutAttendance();
    }

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
  }

  static Future<void> checkAndRegisterTask() async {
    // No-op for backwards compatibility during refactor, Native Geofencing handles persistence via OS.
  }
}
