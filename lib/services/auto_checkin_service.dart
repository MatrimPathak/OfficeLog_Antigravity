import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
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

      Position position = await Geolocator.getCurrentPosition();

      double distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        profile.officeLat!,
        profile.officeLng!,
      );

      // Threshold: 200 meters
      if (distance <= 200) {
        // Check if already logged today
        final attendanceService = ref.read(attendanceServiceProvider);
        if (attendanceService == null) return;

        final today = DateTime.now();
        final logsStream = attendanceService.getAttendanceStream(
          today,
        ); // Gets months logs
        final logs = await logsStream.first;

        final isLogged = logs.any(
          (log) => StatsCalculator.isSameDay(log.date, today),
        );

        if (!isLogged) {
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
        }
      }
    } catch (e) {
      // log error
    }
  }
}

final autoCheckInServiceProvider = Provider<AutoCheckInService>(
  (ref) => AutoCheckInService(ref),
);
