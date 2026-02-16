import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/auth_service.dart';
import '../../services/attendance_service.dart';
import '../../data/models/user_profile.dart'; // Add this import
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/notification_service.dart';

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

final currentYearProvider = NotifierProvider<CurrentYearNotifier, int>(
  CurrentYearNotifier.new,
);

class CurrentYearNotifier extends Notifier<int> {
  @override
  int build() => DateTime.now().year;
  void update(int year) => state = year;
}

final yearlyAttendanceProvider = StreamProvider<List<dynamic>>((ref) {
  // dynamic to avoid circle
  final service = ref.watch(attendanceServiceProvider);
  final year = ref.watch(currentYearProvider);

  if (service != null) {
    return service.getYearlyAttendanceStream(year);
  }
  return Stream.value([]);
});

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);

class ThemeModeNotifier extends Notifier<ThemeMode> {
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
  }
}

final notificationEnabledProvider =
    NotifierProvider<NotificationEnabledNotifier, bool>(
      NotificationEnabledNotifier.new,
    );

class NotificationEnabledNotifier extends Notifier<bool> {
  @override
  bool build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return prefs.getBool('notifications_enabled') ?? false;
  }

  Future<void> toggle(bool value) async {
    state = value;
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setBool('notifications_enabled', value);

    final user = ref.read(currentUserProvider);
    if (user != null) {
      // Get other settings to keep them in sync/don't overwrite with null if we were doing a merge,
      // but here we are key-value pairing so it's fine.
      // However, to be safe and clean, let's update just this key or all.
      // Firestore update with dot notation for nested fields is 'settings.notifications_enabled'
      // But our updateUserSettings takes a Map and replaces 'settings' field or updates it?
      // AuthService.updateUserSettings uses .update({'settings': settings}), which REPLACES the map.
      // We should probably change AuthService to use SetOptions(merge: true) or update specific fields.
      // OR, we just explicitly send all current local settings.
      final themeIndex = ref.read(themeModeProvider).index;
      final time = ref.read(notificationTimeProvider);

      await ref.read(authServiceProvider).updateUserSettings(user.uid, {
        'notifications_enabled': value,
        'theme_mode': themeIndex,
        'notification_hour': time.hour,
        'notification_minute': time.minute,
      });
    }

    if (value) {
      await NotificationService.requestPermissions();
      final time = ref.read(notificationTimeProvider);
      await NotificationService.scheduleDailyNotification(time);
    } else {
      await NotificationService.cancelAllNotifications();
    }
  }
}

final notificationTimeProvider =
    NotifierProvider<NotificationTimeNotifier, TimeOfDay>(
      NotificationTimeNotifier.new,
    );

class NotificationTimeNotifier extends Notifier<TimeOfDay> {
  @override
  TimeOfDay build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    // TODO: Ideally we should check if UserProfile has settings and use them if local prefs are missing?
    // But currently we rely on local prefs as source of truth for UI, and sync to remote.
    // To support "Remote > Local" sync (e.g. fresh install), we would need a listener on UserProfile.
    // For now, adhering to "Make all settings persistent like save it to the database".
    final hour = prefs.getInt('notification_hour') ?? 9;
    final minute = prefs.getInt('notification_minute') ?? 0;
    return TimeOfDay(hour: hour, minute: minute);
  }

  Future<void> update(TimeOfDay time) async {
    state = time;
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setInt('notification_hour', time.hour);
    await prefs.setInt('notification_minute', time.minute);

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

    if (ref.read(notificationEnabledProvider)) {
      await NotificationService.cancelAllNotifications();
      await NotificationService.scheduleDailyNotification(time);
    }
  }
}

final dynamicIconEnabledProvider =
    NotifierProvider<DynamicIconEnabledNotifier, bool>(
      DynamicIconEnabledNotifier.new,
    );

class DynamicIconEnabledNotifier extends Notifier<bool> {
  @override
  bool build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return prefs.getBool('dynamic_icon_enabled') ?? false;
  }

  Future<void> toggle(bool value) async {
    state = value;
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setBool('dynamic_icon_enabled', value);

    final user = ref.read(currentUserProvider);
    if (user != null) {
      // Sync to user profile settings
      await ref.read(authServiceProvider).updateUserSettings(user.uid, {
        'dynamic_icon_enabled': value,
      });
    }
  }
}
