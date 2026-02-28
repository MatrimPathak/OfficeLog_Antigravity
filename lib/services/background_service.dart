import 'package:workmanager/workmanager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:developer' as developer;

import '../presentation/providers/providers.dart';
import 'auto_checkin_service.dart';
import 'notification_service.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    developer.log('BackgroundService: executing task $task');

    // Helper to log persistent background events
    Future<void> logEvent(String message) async {
      try {
        final box = await Hive.openBox<String>('background_logs');
        final timestamp = DateTime.now().toIso8601String();
        await box.add('[$timestamp] $message');
        if (box.length > 100) await box.deleteAt(0); // Keep last 100 logs
      } catch (e) {
        developer.log('Failed to write to Hive log: $e');
      }
    }

    try {
      // Initialize necessary services
      await Firebase.initializeApp();
      await Hive.initFlutter();
      await logEvent('Task started: $task');
      await NotificationService.init();

      final prefs = await SharedPreferences.getInstance();

      // We need a temporary container to use our providers
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );

      // Trigger the check-in logic
      await container.read(autoCheckInServiceProvider).checkAndLogAttendance();

      await logEvent('Task completed successfully');

      // Cleanup
      container.dispose();

      return true;
    } catch (e, stack) {
      developer.log(
        'BackgroundService: error executing task $task: $e\n$stack',
      );
      try {
        await Hive.initFlutter();
        final box = await Hive.openBox<String>('background_logs');
        await box.add('[${DateTime.now().toIso8601String()}] ERROR: $e');
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
      developer.log('BackgroundService: Failed to init geofence: $e');
    }

    developer.log('BackgroundService: initialized');
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
    developer.log('BackgroundService: periodic task registered (keep policy)');
  }

  /// Automatically registers the background task if location permission is granted
  static Future<void> checkAndRegisterTask() async {
    var status = await Permission.locationAlways.status;
    if (status.isGranted) {
      developer.log(
        'BackgroundService: LocationAlways granted, autonomously registering task on startup.',
      );
      await registerPeriodicTask();
    } else {
      developer.log(
        'BackgroundService: LocationAlways not granted, skipping auto-registration.',
      );
    }
  }
}
