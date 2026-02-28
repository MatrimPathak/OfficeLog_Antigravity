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

  static Future<void> scheduleSmartNotifications({
    required TimeOfDay time,
    required List<DateTime> holidays,
    required List<DateTime> loggedDates,
  }) async {
    await cancelAllNotifications();

    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    developer.log(
      'NotificationService: scheduling smart notifications '
      '(hour: ${time.hour}, minute: ${time.minute})',
    );

    int scheduledCount = 0;
    int daysOffset = 0;

    // Schedule exact notifications for the next 14 valid working days
    while (scheduledCount < 14 && daysOffset < 30) {
      tz.TZDateTime dateToEvaluate = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day,
        time.hour,
        time.minute,
      ).add(Duration(days: daysOffset));

      // Skip today if the time has already passed
      if (dateToEvaluate.isBefore(now)) {
        daysOffset++;
        continue;
      }

      // Check 1: Weekend
      if (dateToEvaluate.weekday == DateTime.saturday ||
          dateToEvaluate.weekday == DateTime.sunday) {
        daysOffset++;
        continue;
      }

      // Check 2: Holiday
      bool isHoliday = holidays.any(
        (h) =>
            h.year == dateToEvaluate.year &&
            h.month == dateToEvaluate.month &&
            h.day == dateToEvaluate.day,
      );
      if (isHoliday) {
        daysOffset++;
        continue;
      }

      // Check 3: Already Logged
      bool isLogged = loggedDates.any(
        (l) =>
            l.year == dateToEvaluate.year &&
            l.month == dateToEvaluate.month &&
            l.day == dateToEvaluate.day,
      );
      if (isLogged) {
        daysOffset++;
        continue;
      }

      // Passed checks! Schedule exact notification
      int notificationId = 100 + scheduledCount; // Avoid 1..5 collisions
      await _scheduleExactNotification(notificationId, dateToEvaluate);

      scheduledCount++;
      daysOffset++;
    }

    final pending = await _notificationsPlugin.pendingNotificationRequests();
    developer.log(
      'NotificationService: ${pending.length} pending exact notifications scheduled.',
    );
  }

  static Future<void> _scheduleExactNotification(
    int id,
    tz.TZDateTime scheduledDate,
  ) async {
    await _notificationsPlugin.zonedSchedule(
      id: id,
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
        ),
        iOS: DarwinNotificationDetails(),
        macOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
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
