import 'package:workmanager/workmanager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';

import '../presentation/providers/providers.dart';
import 'auto_checkin_service.dart';
import 'notification_service.dart';
import 'logger_service.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    LoggerService.instance.info('BackgroundService: executing task $task');

    // Helper to log persistent background events
    try {
      // Initialize necessary services
      await Firebase.initializeApp();
      await Hive.initFlutter();
      LoggerService.instance.background('Task started: $task');
      await NotificationService.init();

      final prefs = await SharedPreferences.getInstance();

      // We need a temporary container to use our providers
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );

      // Trigger the check-in logic
      await container.read(autoCheckInServiceProvider).checkAndLogAttendance();

      LoggerService.instance.background('Task completed successfully');

      // Cleanup
      container.dispose();

      return true;
    } catch (e, stack) {
      try {
        await Hive.initFlutter();
        LoggerService.instance.error(
          'BackgroundService: error executing task $task: $e\n$stack',
        );
      } catch (_) {}
      return false;
    }
  });
}

class BackgroundService {
  static Future<void> init(ProviderContainer container) async {
    await Workmanager().initialize(callbackDispatcher);

    // Initialize Geofencing
    try {
      await container.read(autoCheckInServiceProvider).initGeofence();
    } catch (e) {
      LoggerService.instance.error(
        'BackgroundService: Failed to init geofence: $e',
      );
    }

    LoggerService.instance.info('BackgroundService: initialized');
  }

  static Future<void> registerPeriodicTask() async {
    await Workmanager().registerPeriodicTask(
      'autoCheckInTask', // Unique name
      'autoCheckIn', // Task name to identify in dispatcher
      frequency: const Duration(minutes: 15),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy
          .update, // Ensure settings are updated on registration
    );
    LoggerService.instance.info(
      'BackgroundService: periodic task registered (keep policy)',
    );
  }

  /// Automatically registers the background task if location permission is granted
  static Future<void> checkAndRegisterTask() async {
    var status = await Permission.locationAlways.status;
    if (status.isGranted) {
      LoggerService.instance.info(
        'BackgroundService: LocationAlways granted, autonomously registering task on startup.',
      );
      await registerPeriodicTask();
    } else {
      LoggerService.instance.info(
        'BackgroundService: LocationAlways not granted, skipping auto-registration.',
      );
    }
  }
}
