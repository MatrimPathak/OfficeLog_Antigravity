import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:developer' as developer;
import '../data/models/attendance_log.dart';
import '../presentation/providers/providers.dart';
import '../logic/stats_calculator.dart';
import '../services/notification_service.dart';

class AutoCheckInService {
  final Ref ref;

  AutoCheckInService(this.ref);

  Future<void> checkAndLogAttendance() async {
    try {
      final user = ref.read(currentUserProvider);
      if (user == null) return;

      // --- EARLY EXIT OPTIMIZATIONS ---
      final today = DateTime.now();

      // 1. Workday-Only Check
      if (today.weekday == DateTime.saturday ||
          today.weekday == DateTime.sunday) {
        developer.log('AutoCheckIn: Weekend, skipping check-in.');
        return;
      }

      // 2. Time-of-Day Window (6:00 AM to 6:00 PM)
      if (today.hour < 6 || today.hour >= 18) {
        developer.log('AutoCheckIn: Outside time window (6am-6pm), skipping.');
        return;
      }

      // 3. Already Checked-In Short-Circuit
      final attendanceService = ref.read(attendanceServiceProvider);
      if (attendanceService == null) return;

      final logsStream = attendanceService.getAttendanceStream(today);
      final logs = await logsStream.first;
      final isLogged = logs.any(
        (log) => StatsCalculator.isSameDay(log.date, today),
      );

      if (isLogged) {
        developer.log('AutoCheckIn: Already logged today, skipping.');
        return;
      }
      // --------------------------------

      // Fetch profile directly
      final profileStream = ref
          .read(authServiceProvider)
          .getUserProfile(user.uid);
      final profile = await profileStream.first;

      if (profile == null ||
          profile.officeLat == null ||
          profile.officeLng == null) {
        return;
      }

      // Check permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        // Silently fail or log error
        return;
      }

      // Robust Background Location Fetching
      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium, // Sufficient for 200m radius
            timeLimit: Duration(
              seconds: 15,
            ), // Don't hang the background task forever
          ),
        );
      } catch (e) {
        developer.log(
          'AutoCheckIn: Failed precise location, trying last known: $e',
        );
        position = await Geolocator.getLastKnownPosition();
      }

      if (position == null) {
        developer.log('AutoCheckIn: Could not determine location.');
        return;
      }

      double distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        profile.officeLat!,
        profile.officeLng!,
      );

      developer.log('AutoCheckIn: Distance to office is $distance meters');

      // Threshold: 200 meters
      if (distance <= 200) {
        final log = AttendanceLog(
          id: '${user.uid}_${today.millisecondsSinceEpoch}',
          userId: user.uid,
          date: today,
          timestamp: today,
          method: 'auto',
        );
        await attendanceService.logAttendance(log);
        await NotificationService.showNotification(
          'Auto Check-in',
          'You have been checked in!',
        );
        developer.log(
          'AutoCheckIn: Successfully logged attendance via background task.',
        );
      }
    } catch (e, stack) {
      developer.log('AutoCheckIn error: $e\n$stack');
    }
  }
}

final autoCheckInServiceProvider = Provider<AutoCheckInService>(
  (ref) => AutoCheckInService(ref),
);
