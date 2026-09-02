import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/auth_service.dart';
import '../../services/attendance_service.dart';
import '../../services/planned_days_service.dart';
import '../../data/models/user_profile.dart'; // Add this import
import '../../data/models/attendance_rules.dart';
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

final backgroundLocationPermissionProvider = FutureProvider<bool>((ref) async {
  return await Permission.locationAlways.isGranted;
});

final notificationPermissionProvider = FutureProvider<bool>((ref) async {
  return await Permission.notification.isGranted;
});

/// Optional — activity recognition is used by the automatic attendance
/// detection engine as one of several evidence signals, never a required
/// dependency (see docs/AUTO_ATTENDANCE_DESIGN.md section 4). Uses
/// `permission_handler`'s own `Permission.activityRecognition`, which maps
/// to Android's ACTIVITY_RECOGNITION runtime permission and iOS's motion
/// permission, rather than depending on the activity-recognition plugin's
/// own permission check here (keeping this provider plugin-agnostic).
final activityRecognitionPermissionProvider = FutureProvider<bool>((ref) async {
  return await Permission.activityRecognition.isGranted;
});

final autoCheckInEnabledProvider =
    NotifierProvider<AutoCheckInEnabledNotifier, bool>(
      AutoCheckInEnabledNotifier.new,
    );

class AutoCheckInEnabledNotifier extends Notifier<bool> {
  Timer? _debounce;

  @override
  bool build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return prefs.getBool('auto_checkin_enabled') ?? false;
  }

  Future<void> toggle(bool value) async {
    state = value;
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setBool('auto_checkin_enabled', value);

    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () async {
      final user = ref.read(currentUserProvider);
      if (user != null) {
        await ref.read(authServiceProvider).updateUserSettings(user.uid, {
          'auto_checkin_enabled': value,
          'theme_mode': ref.read(themeModeProvider).index,
          'notifications_enabled': ref.read(notificationEnabledProvider),
          'notification_hour': ref.read(notificationTimeProvider).hour,
          'notification_minute': ref.read(notificationTimeProvider).minute,
          'geofence_radius': ref.read(geofenceRadiusProvider),
          'calculateHolidayAsWorking': ref.read(calculateHolidayAsWorkingProvider),
          'captureCheckInOut': ref.read(captureCheckInOutProvider),
          'attendanceRulesConfig': ref.read(attendanceRulesConfigProvider).toMap(),
        });
      }
    });
  }

  /// Applies a value restored from the remote profile, without re-publishing
  /// it back to Firestore. Used to seed local state on a fresh install/device.
  Future<void> hydrate(bool value) async {
    state = value;
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setBool('auto_checkin_enabled', value);
  }
}

final geofenceRadiusProvider = NotifierProvider<GeofenceRadiusNotifier, int>(
  GeofenceRadiusNotifier.new,
);

class GeofenceRadiusNotifier extends Notifier<int> {
  Timer? _debounce;

  @override
  int build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return prefs.getInt('geofence_radius') ?? 100;
  }

  Future<void> update(int value) async {
    if (value < 10) value = 10; // Minimum sanity check
    state = value;
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setInt('geofence_radius', value);

    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () async {
      final user = ref.read(currentUserProvider);
      if (user != null) {
        await ref.read(authServiceProvider).updateUserSettings(user.uid, {
          'geofence_radius': value,
          'auto_checkin_enabled': ref.read(autoCheckInEnabledProvider),
          'theme_mode': ref.read(themeModeProvider).index,
          'notifications_enabled': ref.read(notificationEnabledProvider),
          'notification_hour': ref.read(notificationTimeProvider).hour,
          'notification_minute': ref.read(notificationTimeProvider).minute,
          'calculateHolidayAsWorking': ref.read(calculateHolidayAsWorkingProvider),
          'captureCheckInOut': ref.read(captureCheckInOutProvider),
          'attendanceRulesConfig': ref.read(attendanceRulesConfigProvider).toMap(),
        });
      }
    });
  }

  /// Applies a value restored from the remote profile, without re-publishing
  /// it back to Firestore. Used to seed local state on a fresh install/device.
  Future<void> hydrate(int value) async {
    state = value;
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setInt('geofence_radius', value);
  }
}

/// Optional workplace Wi-Fi network name (SSID) used by the automatic
/// attendance detection engine's NetworkEvidence signal — see
/// docs/AUTO_ATTENDANCE_DESIGN.md sections 4 and 10. Deliberately local-only
/// (SharedPreferences, not synced to Firestore/`updateUserSettings`): it's a
/// per-device convenience for an Android-only, already-optional signal, not
/// a rule the rest of the app needs to reason about. An empty/null value
/// simply means the engine never gets a positive network signal, which the
/// confidence engine already treats as "unavailable" rather than negative.
final workplaceWifiSsidProvider =
    NotifierProvider<WorkplaceWifiSsidNotifier, String?>(
      WorkplaceWifiSsidNotifier.new,
    );

class WorkplaceWifiSsidNotifier extends Notifier<String?> {
  @override
  String? build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final value = prefs.getString('workplace_wifi_ssid');
    return (value == null || value.isEmpty) ? null : value;
  }

  Future<void> update(String? ssid) async {
    final trimmed = ssid?.trim();
    state = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString('workplace_wifi_ssid', state ?? '');
  }
}

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
          'auto_checkin_enabled': ref.read(autoCheckInEnabledProvider),
          'geofence_radius': ref.read(geofenceRadiusProvider),
          'calculateHolidayAsWorking': ref.read(calculateHolidayAsWorkingProvider),
          'captureCheckInOut': ref.read(captureCheckInOutProvider),
          'attendanceRulesConfig': ref.read(attendanceRulesConfigProvider).toMap(),
        });
      }
    });
  }

  /// Applies a value restored from the remote profile, without re-publishing
  /// it back to Firestore. Used to seed local state on a fresh install/device.
  Future<void> hydrate(ThemeMode mode) async {
    state = mode;
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setInt('theme_mode', mode.index);
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
          'auto_checkin_enabled': ref.read(autoCheckInEnabledProvider),
          'geofence_radius': ref.read(geofenceRadiusProvider),
          'calculateHolidayAsWorking': ref.read(calculateHolidayAsWorkingProvider),
          'captureCheckInOut': ref.read(captureCheckInOutProvider),
          'attendanceRulesConfig': ref.read(attendanceRulesConfigProvider).toMap(),
        });
      }
    });
  }

  /// Applies a value restored from the remote profile, without re-publishing
  /// it back to Firestore or requesting permissions/scheduling notifications.
  /// Used to seed local state on a fresh install/device.
  Future<void> hydrate(bool value) async {
    state = value;
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setBool('notifications_enabled', value);
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
          'auto_checkin_enabled': ref.read(autoCheckInEnabledProvider),
          'geofence_radius': ref.read(geofenceRadiusProvider),
          'calculateHolidayAsWorking': ref.read(calculateHolidayAsWorkingProvider),
          'captureCheckInOut': ref.read(captureCheckInOutProvider),
          'attendanceRulesConfig': ref.read(attendanceRulesConfigProvider).toMap(),
        });
      }
    });
  }

  /// Applies a value restored from the remote profile, without re-publishing
  /// it back to Firestore or rescheduling notifications. Used to seed local
  /// state on a fresh install/device.
  Future<void> hydrate(TimeOfDay time) async {
    state = time;
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setInt('notification_hour', time.hour);
    await prefs.setInt('notification_minute', time.minute);
  }
}

final calculateHolidayAsWorkingProvider =
    NotifierProvider<CalculateHolidayAsWorkingNotifier, bool>(
      CalculateHolidayAsWorkingNotifier.new,
    );

class CalculateHolidayAsWorkingNotifier extends Notifier<bool> {
  Timer? _debounce;

  @override
  bool build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return prefs.getBool('calculateHolidayAsWorking') ?? false;
  }

  Future<void> toggle(bool value) async {
    state = value;
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setBool('calculateHolidayAsWorking', value);

    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () async {
      final user = ref.read(currentUserProvider);
      if (user != null) {
        await ref.read(authServiceProvider).updateUserSettings(user.uid, {
          'calculateHolidayAsWorking': value,
          'theme_mode': ref.read(themeModeProvider).index,
          'notifications_enabled': ref.read(notificationEnabledProvider),
          'notification_hour': ref.read(notificationTimeProvider).hour,
          'notification_minute': ref.read(notificationTimeProvider).minute,
          'auto_checkin_enabled': ref.read(autoCheckInEnabledProvider),
          'geofence_radius': ref.read(geofenceRadiusProvider),
          'captureCheckInOut': ref.read(captureCheckInOutProvider),
          'attendanceRulesConfig': ref.read(attendanceRulesConfigProvider).toMap(),
        });
      }
    });
  }

  /// Applies a value restored from the remote profile, without re-publishing
  /// it back to Firestore. Used to seed local state on a fresh install/device.
  Future<void> hydrate(bool value) async {
    state = value;
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setBool('calculateHolidayAsWorking', value);
  }
}

final captureCheckInOutProvider =
    NotifierProvider<CaptureCheckInOutNotifier, bool>(
      CaptureCheckInOutNotifier.new,
    );

class CaptureCheckInOutNotifier extends Notifier<bool> {
  Timer? _debounce;

  @override
  bool build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return prefs.getBool('captureCheckInOut') ?? true;
  }

  Future<void> toggle(bool value) async {
    state = value;
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setBool('captureCheckInOut', value);

    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () async {
      final user = ref.read(currentUserProvider);
      if (user != null) {
        await ref.read(authServiceProvider).updateUserSettings(user.uid, {
          'captureCheckInOut': value,
          'theme_mode': ref.read(themeModeProvider).index,
          'notifications_enabled': ref.read(notificationEnabledProvider),
          'notification_hour': ref.read(notificationTimeProvider).hour,
          'notification_minute': ref.read(notificationTimeProvider).minute,
          'auto_checkin_enabled': ref.read(autoCheckInEnabledProvider),
          'geofence_radius': ref.read(geofenceRadiusProvider),
          'calculateHolidayAsWorking': ref.read(calculateHolidayAsWorkingProvider),
          'attendanceRulesConfig': ref.read(attendanceRulesConfigProvider).toMap(),
        });
      }
    });
  }

  /// Applies a value restored from the remote profile, without re-publishing
  /// it back to Firestore. Used to seed local state on a fresh install/device.
  Future<void> hydrate(bool value) async {
    state = value;
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setBool('captureCheckInOut', value);
  }
}

final attendanceRulesConfigProvider =
    NotifierProvider<AttendanceRulesConfigNotifier, AttendanceRulesConfig>(
      AttendanceRulesConfigNotifier.new,
    );

class AttendanceRulesConfigNotifier extends Notifier<AttendanceRulesConfig> {
  Timer? _debounce;

  @override
  AttendanceRulesConfig build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final jsonStr = prefs.getString('attendance_rules_config');
    if (jsonStr == null) return AttendanceRulesConfig.defaultConfig;
    try {
      return AttendanceRulesConfig.fromMap(
        jsonDecode(jsonStr) as Map<String, dynamic>,
      );
    } catch (_) {
      return AttendanceRulesConfig.defaultConfig;
    }
  }

  Future<void> update(AttendanceRulesConfig config) async {
    state = config;
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString('attendance_rules_config', jsonEncode(config.toMap()));

    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () async {
      final user = ref.read(currentUserProvider);
      if (user != null) {
        await ref.read(authServiceProvider).updateUserSettings(user.uid, {
          'attendanceRulesConfig': config.toMap(),
          'theme_mode': ref.read(themeModeProvider).index,
          'notifications_enabled': ref.read(notificationEnabledProvider),
          'notification_hour': ref.read(notificationTimeProvider).hour,
          'notification_minute': ref.read(notificationTimeProvider).minute,
          'auto_checkin_enabled': ref.read(autoCheckInEnabledProvider),
          'geofence_radius': ref.read(geofenceRadiusProvider),
          'calculateHolidayAsWorking': ref.read(calculateHolidayAsWorkingProvider),
          'captureCheckInOut': ref.read(captureCheckInOutProvider),
        });
      }
    });
  }

  /// Applies a value restored from the remote profile, without re-publishing
  /// it back to Firestore. Used to seed local state on a fresh install/device.
  Future<void> hydrate(AttendanceRulesConfig config) async {
    state = config;
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString('attendance_rules_config', jsonEncode(config.toMap()));
  }
}

Future<void> refreshSmartNotifications(
  dynamic ref, {
  bool? isEnabled,
  TimeOfDay? targetTime,
}) async {
  // Cancel immediately to prevent any pending notification from firing
  // during the propagation delay window below.
  await NotificationService.cancelAllNotifications();

  // Add a small propagation delay to allow Firestore local cache to update the Streams
  // before we rely on them for scheduling.
  await Future.delayed(const Duration(milliseconds: 300));

  final enabled = isEnabled ?? ref.read(notificationEnabledProvider);
  if (!enabled) {
    await NotificationService.cancelAllNotifications();
    return;
  }

  final user = ref.read(currentUserProvider);
  if (user == null) return;

  final time = targetTime ?? ref.read(notificationTimeProvider);
  final holidays = ref.read(holidaysStreamProvider).value ?? <DateTime>[];
  final calculateHolidayAsWorking = ref.read(calculateHolidayAsWorkingProvider);
  final workingWeekdays = ref.read(attendanceRulesConfigProvider).workingWeekdays;

  final currentYear = DateTime.now().year;
  final logsAsync = ref.read(yearlyAttendanceProvider(currentYear));
  final Set<DateTime> loggedDatesSet = {};

  // 1. Add dates from Firestore
  if (logsAsync.value != null) {
    for (var log in logsAsync.value!) {
      loggedDatesSet.add(log.date as DateTime);
    }
  }

  // 2. Add dates from local Hive cache (More authoritative for immediate feedback)
  final service = AttendanceService(user.uid);
  final cachedDates = await service.getCachedLoggedDates();
  loggedDatesSet.addAll(cachedDates);

  await NotificationService.scheduleSmartNotifications(
    time: time,
    holidays: holidays,
    loggedDates: loggedDatesSet.toList(),
    calculateHolidayAsWorking: calculateHolidayAsWorking,
    workingWeekdays: workingWeekdays,
  );
}

// Provider to keep notifications in sync with attendance state
final notificationSchedulerProvider = Provider<void>((ref) {
  final isEnabled = ref.watch(notificationEnabledProvider);
  if (!isEnabled) return;

  final currentYear = DateTime.now().year;
  
  ref.listen(yearlyAttendanceProvider(currentYear), (previous, next) {
    refreshSmartNotifications(ref);
  });
  
  ref.listen(holidaysStreamProvider, (previous, next) {
    refreshSmartNotifications(ref);
  });

  ref.listen(notificationTimeProvider, (previous, next) {
    refreshSmartNotifications(ref);
  });

  ref.listen(calculateHolidayAsWorkingProvider, (previous, next) {
    refreshSmartNotifications(ref);
  });

  ref.listen(attendanceRulesConfigProvider, (previous, next) {
    refreshSmartNotifications(ref);
  });
});

// Planned office days for leave planning (stored in Firestore: users/{uid}/planned)
final plannedDaysServiceProvider = Provider<PlannedDaysService?>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user != null) {
    return PlannedDaysService(user.uid);
  }
  return null;
});

final plannedDatesProvider = StreamProvider<List<DateTime>>((ref) {
  final service = ref.watch(plannedDaysServiceProvider);
  if (service != null) {
    return service.getPlannedDatesStream();
  }
  return Stream.value([]);
});

const _settingsHydratedKey = 'settings_hydrated_from_remote';

/// Seeds local settings from the remote profile's `settings` map the first
/// time this device/install sees it (guarded by [_settingsHydratedKey]).
///
/// Every settings toggle in this app is local-first: it updates in-memory
/// state and SharedPreferences immediately, then debounces a full snapshot
/// up to Firestore. Nothing previously read that snapshot back, so a value
/// set on one device (or before local data was cleared) was invisible on a
/// fresh install, which silently reset every toggle to its default. This
/// runs once per install to restore the last-synced values, after which
/// local state is authoritative again for the rest of that install's
/// lifetime, same as before.
Future<void> hydrateSettingsFromRemote(
  dynamic ref,
  Map<String, dynamic> settings,
) async {
  final prefs = ref.read(sharedPreferencesProvider) as SharedPreferences;
  if (prefs.getBool(_settingsHydratedKey) ?? false) return;

  final themeIndex = settings['theme_mode'];
  if (themeIndex is int && themeIndex >= 0 && themeIndex < ThemeMode.values.length) {
    await ref.read(themeModeProvider.notifier).hydrate(ThemeMode.values[themeIndex]);
  }

  final notificationsEnabled = settings['notifications_enabled'];
  if (notificationsEnabled is bool) {
    await ref.read(notificationEnabledProvider.notifier).hydrate(notificationsEnabled);
  }

  final notificationHour = settings['notification_hour'];
  final notificationMinute = settings['notification_minute'];
  if (notificationHour is int || notificationMinute is int) {
    final current = ref.read(notificationTimeProvider) as TimeOfDay;
    await ref.read(notificationTimeProvider.notifier).hydrate(
          TimeOfDay(
            hour: notificationHour is int ? notificationHour : current.hour,
            minute: notificationMinute is int ? notificationMinute : current.minute,
          ),
        );
  }

  final autoCheckInEnabled = settings['auto_checkin_enabled'];
  if (autoCheckInEnabled is bool) {
    await ref.read(autoCheckInEnabledProvider.notifier).hydrate(autoCheckInEnabled);
  }

  final geofenceRadius = settings['geofence_radius'];
  if (geofenceRadius is int) {
    await ref.read(geofenceRadiusProvider.notifier).hydrate(geofenceRadius);
  }

  final calculateHolidayAsWorking = settings['calculateHolidayAsWorking'];
  if (calculateHolidayAsWorking is bool) {
    await ref
        .read(calculateHolidayAsWorkingProvider.notifier)
        .hydrate(calculateHolidayAsWorking);
  }

  final captureCheckInOut = settings['captureCheckInOut'];
  if (captureCheckInOut is bool) {
    await ref.read(captureCheckInOutProvider.notifier).hydrate(captureCheckInOut);
  }

  final attendanceRulesConfig = settings['attendanceRulesConfig'];
  if (attendanceRulesConfig is Map) {
    try {
      final config = AttendanceRulesConfig.fromMap(
        Map<String, dynamic>.from(attendanceRulesConfig),
      );
      await ref.read(attendanceRulesConfigProvider.notifier).hydrate(config);
    } catch (_) {
      // Malformed remote config; keep local defaults.
    }
  }

  await prefs.setBool(_settingsHydratedKey, true);
}
