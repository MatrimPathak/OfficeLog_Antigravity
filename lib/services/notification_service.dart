import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter/material.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'dart:developer' as developer;

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        );

    const InitializationSettings initializationSettings =
        InitializationSettings(
          android: initializationSettingsAndroid,
          iOS: initializationSettingsDarwin,
          macOS: initializationSettingsDarwin,
        );

    await _notificationsPlugin.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );
    tz.initializeTimeZones();

    // Detect the device's local timezone and set it
    final String timeZoneName = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(timeZoneName));
    developer.log('NotificationService: timezone set to $timeZoneName');
  }

  static void _onNotificationTapped(NotificationResponse response) {
    developer.log('NotificationService: notification tapped: ${response.id}');
  }

  static Future<void> showNotification(String title, String body) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'office_log_channel',
          'Office Log Notifications',
          channelDescription: 'Notifications for Office Log App',
          importance: Importance.max,
          priority: Priority.high,
        );

    const DarwinNotificationDetails darwinDetails = DarwinNotificationDetails();

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );

    await _notificationsPlugin.show(
      id: 0,
      title: title,
      body: body,
      notificationDetails: details,
    );
  }

  static Future<void> scheduleDailyNotification(TimeOfDay time) async {
    // Cancel any existing daily reminder first to avoid duplicates or stale times
    await cancelDailyNotification();

    final scheduledDate = _nextInstanceOfTime(time);
    developer.log(
      'NotificationService: scheduling daily notification at $scheduledDate '
      '(hour: ${time.hour}, minute: ${time.minute})',
    );

    await _notificationsPlugin.zonedSchedule(
      id: 1, // Fixed ID for daily reminder
      title: 'Check Attendance',
      body: 'Don\'t forget to log your attendance today!',
      scheduledDate: scheduledDate,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'daily_reminder_channel',
          'Daily Reminder',
          channelDescription: 'Daily reminder to log attendance',
          importance: Importance.max,
          priority: Priority.high,
          // Removed largeIcon as background isolates sometimes fail to resolve it
        ),
        iOS: DarwinNotificationDetails(),
        macOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );

    // Verify the notification was scheduled
    final pendingNotifications = await _notificationsPlugin
        .pendingNotificationRequests();
    developer.log(
      'NotificationService: ${pendingNotifications.length} pending notifications: '
      '${pendingNotifications.map((n) => 'id=${n.id} title=${n.title}').join(', ')}',
    );
  }

  static Future<void> cancelDailyNotification() async {
    await _notificationsPlugin.cancel(id: 1);
    developer.log('NotificationService: daily notification (id=1) cancelled');
  }

  /// Schedules the notification for the NEXT day (skipping today)
  /// Used when attendance is logged for the current day.
  static Future<void> scheduleNextDayNotification(TimeOfDay time) async {
    await cancelDailyNotification();

    final now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime scheduledDate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      time.hour,
      time.minute,
    );

    // If scheduled date is today or before, add 1 day to make it tomorrow
    // actually, we WANT it to be tomorrow.
    if (scheduledDate.isBefore(now) ||
        scheduledDate.year == now.year &&
            scheduledDate.month == now.month &&
            scheduledDate.day == now.day) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    developer.log(
      'NotificationService: scheduling NEXT daily notification at $scheduledDate '
      '(hour: ${time.hour}, minute: ${time.minute})',
    );

    await _notificationsPlugin.zonedSchedule(
      id: 1,
      title: 'Check Attendance',
      body: 'Don\'t forget to log your attendance today!',
      scheduledDate: scheduledDate,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'daily_reminder_channel',
          'Daily Reminder',
          channelDescription: 'Daily reminder to log attendance',
          importance: Importance.max,
          priority: Priority.high,
          // Removed largeIcon as background isolates sometimes fail to resolve it
        ),
        iOS: DarwinNotificationDetails(),
        macOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  static tz.TZDateTime _nextInstanceOfTime(TimeOfDay time) {
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    developer.log('NotificationService: tz.local = ${tz.local}, now = $now');
    tz.TZDateTime scheduledDate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      time.hour,
      time.minute,
    );
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }
    return scheduledDate;
  }

  static Future<void> cancelAllNotifications() async {
    await _notificationsPlugin.cancelAll();
    developer.log('NotificationService: all notifications cancelled');
  }

  static Future<void> requestPermissions() async {
    // Android
    final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
        _notificationsPlugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();

    final bool? androidGranted = await androidImplementation
        ?.requestNotificationsPermission();
    developer.log(
      'NotificationService: android notification permission granted: $androidGranted',
    );

    // iOS
    final IOSFlutterLocalNotificationsPlugin? iosImplementation =
        _notificationsPlugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >();

    final bool? iosGranted = await iosImplementation?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );
    developer.log(
      'NotificationService: ios notification permission granted: $iosGranted',
    );

    // macOS
    final MacOSFlutterLocalNotificationsPlugin? macosImplementation =
        _notificationsPlugin
            .resolvePlatformSpecificImplementation<
              MacOSFlutterLocalNotificationsPlugin
            >();

    final bool? macosGranted = await macosImplementation?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );
    developer.log(
      'NotificationService: macos notification permission granted: $macosGranted',
    );
  }
}
