import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/auth_service.dart';
import '../../services/attendance_service.dart';
import '../../data/models/user_profile.dart'; // Add this import
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/notification_service.dart';
import '../../services/admin_service.dart'; // Add this import

import 'package:package_info_plus/package_info_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

// App Info
final packageInfoProvider = FutureProvider<PackageInfo>((ref) async {
  return await PackageInfo.fromPlatform();
});

// Permissions / Device Settings
final locationPermissionProvider = FutureProvider<LocationPermission>((
  ref,
) async {
  return await Geolocator.checkPermission();
});

final batteryOptimizationProvider = FutureProvider<bool>((ref) async {
  return await Permission.ignoreBatteryOptimizations.isGranted;
});

// Auth Providers
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError();
});

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(authServiceProvider).authStateChanges;
});

final currentUserProvider = Provider<User?>((ref) {
  return ref.watch(authStateProvider).value;
});

final userProfileProvider = StreamProvider<UserProfile?>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user != null) {
    return ref.watch(authServiceProvider).getUserProfile(user.uid);
  }
  return Stream.value(null);
});

// Attendance Providers
final attendanceServiceProvider = Provider<AttendanceService?>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user != null) {
    return AttendanceService(user.uid);
  }
  return null;
});

final currentMonthProvider = NotifierProvider<CurrentMonthNotifier, DateTime>(
  CurrentMonthNotifier.new,
);

class CurrentMonthNotifier extends Notifier<DateTime> {
  @override
  DateTime build() => DateTime.now();
  void update(DateTime date) => state = date;
}

final monthlyAttendanceProvider = StreamProvider<List<dynamic>>((ref) {
  final service = ref.watch(attendanceServiceProvider);
  final month = ref.watch(currentMonthProvider);

  if (service != null) {
    return service.getAttendanceStream(month);
  }
  return Stream.value([]);
});

final summaryYearProvider = NotifierProvider<SummaryYearNotifier, int>(
  SummaryYearNotifier.new,
);

class SummaryYearNotifier extends Notifier<int> {
  @override
  int build() => DateTime.now().year;
  void update(int year) => state = year;
}

final yearlyAttendanceProvider = StreamProvider.family<List<dynamic>, int>((
  ref,
  year,
) {
  // dynamic to avoid circle
  final service = ref.watch(attendanceServiceProvider);

  if (service != null) {
    return service.getYearlyAttendanceStream(year);
  }
  return Stream.value([]);
});

final activeYearsProvider = FutureProvider<List<int>>((ref) async {
  final service = ref.watch(attendanceServiceProvider);
  if (service != null) {
    return await service.getActiveYears();
  }
  return [DateTime.now().year];
});

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  Timer? _debounce;

  @override
  ThemeMode build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final themeIndex =
        prefs.getInt('theme_mode') ?? 0; // 0: system, 1: light, 2: dark
    return ThemeMode.values[themeIndex];
  }

  Future<void> update(ThemeMode mode) async {
    state = mode;
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setInt('theme_mode', mode.index);

    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () async {
      final user = ref.read(currentUserProvider);
      if (user != null) {
        await ref.read(authServiceProvider).updateUserSettings(user.uid, {
          'theme_mode': mode.index,
          'notifications_enabled': ref.read(
            notificationEnabledProvider,
          ), // Sync all
          'notification_hour': ref.read(notificationTimeProvider).hour,
          'notification_minute': ref.read(notificationTimeProvider).minute,
        });
      }
    });
  }
}

final notificationEnabledProvider =
    NotifierProvider<NotificationEnabledNotifier, bool>(
      NotificationEnabledNotifier.new,
    );

class NotificationEnabledNotifier extends Notifier<bool> {
  Timer? _debounce;

  @override
  bool build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return prefs.getBool('notifications_enabled') ?? false;
  }

  Future<void> toggle(bool value) async {
    state = value;
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setBool('notifications_enabled', value);

    if (value) {
      await NotificationService.requestPermissions();
    }
    await refreshSmartNotifications(ref, isEnabled: value);

    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () async {
      final user = ref.read(currentUserProvider);
      if (user != null) {
        final themeIndex = ref.read(themeModeProvider).index;
        final time = ref.read(notificationTimeProvider);

        await ref.read(authServiceProvider).updateUserSettings(user.uid, {
          'notifications_enabled': value,
          'theme_mode': themeIndex,
          'notification_hour': time.hour,
          'notification_minute': time.minute,
        });
      }
    });
  }
}

final notificationTimeProvider =
    NotifierProvider<NotificationTimeNotifier, TimeOfDay>(
      NotificationTimeNotifier.new,
    );

class NotificationTimeNotifier extends Notifier<TimeOfDay> {
  Timer? _debounce;

  @override
  TimeOfDay build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final hour = prefs.getInt('notification_hour') ?? 9;
    final minute = prefs.getInt('notification_minute') ?? 0;
    return TimeOfDay(hour: hour, minute: minute);
  }

  Future<void> update(TimeOfDay time) async {
    state = time;
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setInt('notification_hour', time.hour);
    await prefs.setInt('notification_minute', time.minute);

    if (ref.read(notificationEnabledProvider)) {
      await refreshSmartNotifications(ref, targetTime: time);
    }

    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () async {
      final user = ref.read(currentUserProvider);
      if (user != null) {
        final themeIndex = ref.read(themeModeProvider).index;
        final enabled = ref.read(notificationEnabledProvider);

        await ref.read(authServiceProvider).updateUserSettings(user.uid, {
          'notification_hour': time.hour,
          'notification_minute': time.minute,
          'notifications_enabled': enabled,
          'theme_mode': themeIndex,
        });
      }
    });
  }
}

Future<void> refreshSmartNotifications(
  dynamic ref, {
  bool? isEnabled,
  TimeOfDay? targetTime,
}) async {
  // Add a small propagation delay to allow Firestore local cache to update the Streams
  // before we rely on them for scheduling.
  await Future.delayed(const Duration(milliseconds: 400));

  final enabled = isEnabled ?? ref.read(notificationEnabledProvider);
  if (!enabled) {
    await NotificationService.cancelAllNotifications();
    return;
  }

  final time = targetTime ?? ref.read(notificationTimeProvider);
  final holidays = ref.read(holidaysStreamProvider).value ?? <DateTime>[];

  final currentYear = DateTime.now().year;
  final logsAsync = ref.read(yearlyAttendanceProvider(currentYear));
  final List<DateTime> loggedDates = [];

  if (logsAsync.value != null) {
    for (var log in logsAsync.value!) {
      if (log.date != null) {
        loggedDates.add(log.date as DateTime);
      }
    }
  }

  await NotificationService.scheduleSmartNotifications(
    time: time,
    holidays: holidays,
    loggedDates: loggedDates,
  );
}
