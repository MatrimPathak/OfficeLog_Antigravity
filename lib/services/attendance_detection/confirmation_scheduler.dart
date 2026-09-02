import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:workmanager/workmanager.dart';

import '../logger_service.dart';

/// The single confirming-re-check task this app ever schedules. A stable,
/// fixed identifier (not per-user — one device has at most one active
/// signed-in user at a time, matching the rest of the detection engine's
/// per-device assumptions) so re-scheduling naturally replaces any pending
/// request instead of stacking duplicates.
const String attendanceConfirmationTaskName = 'officelog_attendance_confirmation';

/// Schedules (or cancels) a single deferred "confirming sample" wake-up for
/// the detection engine — the mechanism that lets an in-progress episode
/// (NEAR_WORKPLACE / POSSIBLE_ARRIVAL / POSSIBLE_DEPARTURE) resolve on its
/// own even if no further geofence event or app-foreground check happens to
/// arrive naturally. Without this, an episode that never gets a second
/// signal would sit unresolved forever — see
/// docs/AUTO_ATTENDANCE_DESIGN.md section 6.2.
///
/// Deliberately isolated behind an interface: the engine depends on this,
/// never on `workmanager` directly, and every implementation MUST swallow
/// its own failures — scheduling is a resilience *enhancement*, never a
/// precondition for detection to function (a missed/failed schedule just
/// means the episode falls back to resolving from whatever natural signals
/// arrive, exactly as before this mechanism existed).
abstract class ConfirmationScheduler {
  Future<void> scheduleConfirmation({required Duration delay});
  Future<void> cancelConfirmation();
}

/// [ConfirmationScheduler] backed by `workmanager`.
///
/// The two platforms genuinely differ here (see
/// docs/AUTO_ATTENDANCE_DESIGN.md section 10) and this class deliberately
/// does not pretend otherwise:
///
/// - **Android**: a real WorkManager one-off task (`registerOneOffTask`)
///   with the requested [delay]. Precise, survives process death and
///   device reboot once re-scheduled, and WorkManager itself already
///   handles Doze deferral gracefully — no special-casing needed here.
/// - **iOS**: `registerOneOffTask` in this plugin is *not* a real deferred
///   wake — it is a short `beginBackgroundTask` extension that only helps
///   while the app is already alive, and does not wake a suspended or
///   terminated app later. The genuine Apple mechanism for "wake the app
///   later, even from terminated," is `BGTaskScheduler`, which this plugin
///   exposes as `registerPeriodicTask` (`BGAppRefreshTask`). iOS decides
///   opportunistically *when* to actually run it — there is no precise
///   delay guarantee — so [delay] is honored as a minimum only, and the
///   task recurs (at most every 15 minutes, the platform floor) until
///   [cancelConfirmation] is called once the episode resolves. This is the
///   correct, real Apple API for the job; it is simply not as prompt as
///   Android's, which is an honest platform limitation, not a bug.
class WorkmanagerConfirmationScheduler implements ConfirmationScheduler {
  const WorkmanagerConfirmationScheduler();

  bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<void> scheduleConfirmation({required Duration delay}) async {
    try {
      if (_isAndroid) {
        await Workmanager().registerOneOffTask(
          attendanceConfirmationTaskName,
          attendanceConfirmationTaskName,
          initialDelay: delay,
          existingWorkPolicy: ExistingWorkPolicy.replace,
          constraints: Constraints(networkType: NetworkType.notRequired),
        );
      } else {
        await Workmanager().registerPeriodicTask(
          attendanceConfirmationTaskName,
          attendanceConfirmationTaskName,
          initialDelay: delay,
          frequency: const Duration(minutes: 15),
        );
      }
    } catch (e) {
      LoggerService.instance.error(
        '[AttendanceDetection] failed to schedule confirmation check: $e',
        type: LogType.detection,
      );
    }
  }

  @override
  Future<void> cancelConfirmation() async {
    try {
      await Workmanager().cancelByUniqueName(attendanceConfirmationTaskName);
    } catch (e) {
      LoggerService.instance.error(
        '[AttendanceDetection] failed to cancel confirmation check: $e',
        type: LogType.detection,
      );
    }
  }
}
