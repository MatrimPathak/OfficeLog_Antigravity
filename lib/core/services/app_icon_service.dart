import 'package:flutter_dynamic_icon_plus/flutter_dynamic_icon_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'dart:developer' as developer;

import '../../presentation/providers/providers.dart';
import '../../logic/stats_calculator.dart';
import '../../data/models/attendance_log.dart';

class AppIconService {
  static const String _iconDefault = 'MainActivity';
  static const String _iconDanger = 'MainActivityDanger';
  static const String _iconWarning = 'MainActivityWarning';
  static const String _iconSuccess = 'MainActivitySuccess';

  /// Updates the app icon based on the current attendance status and user settings.
  static Future<void> updateAppIcon(WidgetRef ref) async {
    try {
      final isEnabled = ref.read(dynamicIconEnabledProvider);

      if (!isEnabled) {
        await _setIcon(_iconDefault);
        return;
      }

      final attendanceService = ref.read(attendanceServiceProvider);
      if (attendanceService == null) return;

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      // Get logs for the current month to calculate stats
      // We use a stream in provider, but here we might need a direct fetch
      // or we can read the current value of the monthlyAttendanceProvider if it's available.
      // However, monthlyAttendanceProvider is a StreamProvider.
      // We can try to get the latest value if it's loaded.

      final asyncLogs = ref.read(monthlyAttendanceProvider);
      final List<AttendanceLog> logs =
          asyncLogs.value?.cast<AttendanceLog>() ?? [];

      // If logs are not loaded yet, we might skip or fetch.
      // For now, let's assume this is called when logs are available.

      // 1. Check if logged today
      final hasLoggedToday = logs.any(
        (l) => StatsCalculator.isSameDay(l.date, today),
      );

      if (!hasLoggedToday) {
        await _setIcon(_iconDanger);
        return;
      }

      // 2. Calculate Stats for the current week to determine Warning vs Success
      // We need holidays. Getting them from where?
      // StatsCalculator needs a list of holidays.
      // The app seems to have a way to get holidays.
      // Usually stored in DB or config.
      // Let's check where `SummaryScreen` gets holidays.
      // It likely gets them from a provider or service.
      // For now, let's pass an empty list if we can't easily access them,
      // or check if there is a `holidaysProvider`.

      // Assuming empty holidays for now as a fallback or if not easily available.
      // TODO: Connect to real holiday source.
      final List<DateTime> holidays = [];

      // Calculate start of current week (let's say Monday)
      // DateTime.weekday: Mon=1 ... Sun=7
      // If we assume week starts Monday:
      final startOfWeek = today.subtract(Duration(days: today.weekday - 1));
      final endOfWeek = startOfWeek.add(const Duration(days: 6));

      // Calculate stats
      final stats = StatsCalculator.calculateStats(
        start: startOfWeek,
        end: endOfWeek,
        logs: logs,
        holidays: holidays,
      );

      // Rule: "if user has completed required number of days: success color"
      // "if user has not completed: warning color"
      // We check if (logged >= required)

      // Wait, current week calculation in StatsCalculator calculates required for the *whole* week?
      // "If a week has 3 or less days all are required".
      // If today is Monday, we have 1 working day so far.
      // If we rely on `StatsCalculator` logic, it calculates total required for the range.
      // If the range is the full week, it returns 3 (usually).
      // So if I logged 1 day (Monday), and required is 3. 1 < 3 -> Warning.
      // This matches logically: I haven't completed my weekly quota yet.

      if (stats.logged >= stats.required) {
        await _setIcon(_iconSuccess);
      } else {
        await _setIcon(_iconWarning);
      }
    } catch (e) {
      developer.log('AppIconService: Error updating icon', error: e);
    }
  }

  static Future<void> _setIcon(String iconName) async {
    try {
      final currentIcon = await FlutterDynamicIconPlus.alternateIconName;

      // If current is null, it means default.
      // If iconName is Default, and current is null, do nothing.
      if (iconName == _iconDefault && currentIcon == null) return;

      // If iconName matches current, do nothing.
      if (iconName == currentIcon) return;

      // Note: flutter_dynamic_icon uses null for default icon on iOS.
      // On Android it uses the activity alias name.

      // API difference:
      // iOS: setAlternateIconName(null) for default.
      // Android: setAlternateIconName("MainActivity") assuming that's the default alias?
      // Actually, for Android, the plugin expects the component name (Activity Alias).
      // For default, we usually enable the main component and disable aliases.
      // `flutter_dynamic_icon` handles this if we pass the original activity name?
      // Let's verify how `flutter_dynamic_icon` works for default.
      // Usually passing `null` resets to default.

      if (iconName == _iconDefault) {
        await FlutterDynamicIconPlus.setAlternateIconName(iconName: null);
      } else {
        await FlutterDynamicIconPlus.setAlternateIconName(iconName: iconName);
      }

      developer.log('AppIconService: Icon changed to $iconName');
    } on PlatformException catch (e) {
      developer.log('AppIconService: PlatformException setting icon', error: e);
    } catch (e) {
      developer.log('AppIconService: Error setting icon', error: e);
    }
  }
}
