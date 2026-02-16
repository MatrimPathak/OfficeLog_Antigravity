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

    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);

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

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
    );

    await _notificationsPlugin.show(
      id: 0,
      title: title,
      body: body,
      notificationDetails: details,
    );
  }

  static Future<void> scheduleDailyNotification(TimeOfDay time) async {
    final scheduledDate = _nextInstanceOfTime(time);
    developer.log(
      'NotificationService: scheduling daily notification at $scheduledDate '
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
          largeIcon: DrawableResourceAndroidBitmap(
            '@mipmap/ic_launcher_danger',
          ),
        ),
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
    final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
        _notificationsPlugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();

    final bool? notifGranted = await androidImplementation
        ?.requestNotificationsPermission();
    developer.log(
      'NotificationService: notification permission granted: $notifGranted',
    );
  }
}
