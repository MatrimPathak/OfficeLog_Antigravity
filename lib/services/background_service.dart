import 'package:workmanager/workmanager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:developer' as developer;

import '../presentation/providers/providers.dart';
import 'auto_checkin_service.dart';
import 'notification_service.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    developer.log('BackgroundService: executing task $task');

    try {
      // Initialize necessary services
      await Firebase.initializeApp();
      await Hive.initFlutter();
      await NotificationService.init();

      final prefs = await SharedPreferences.getInstance();

      // We need a temporary container to use our providers
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );

      // Trigger the check-in logic
      await container.read(autoCheckInServiceProvider).checkAndLogAttendance();

      // Cleanup
      container.dispose();

      return true;
    } catch (e) {
      developer.log('BackgroundService: error executing task $task: $e');
      return false;
    }
  });
}

class BackgroundService {
  static Future<void> init() async {
    await Workmanager().initialize(callbackDispatcher);
    developer.log('BackgroundService: initialized');
  }

  static Future<void> registerPeriodicTask() async {
    await Workmanager().registerPeriodicTask(
      'autoCheckInTask',
      'autoCheckIn',
      frequency: const Duration(minutes: 15),
      constraints: Constraints(networkType: NetworkType.connected),
    );
    developer.log('BackgroundService: periodic task registered');
  }
}
