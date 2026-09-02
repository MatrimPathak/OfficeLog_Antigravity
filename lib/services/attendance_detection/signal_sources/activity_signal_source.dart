import 'package:flutter_activity_recognition/flutter_activity_recognition.dart';

import '../../logger_service.dart';
import '../detection_models.dart';

/// Narrow interface the shared detection engine depends on for motion/
/// activity evidence. Isolated so the concrete plugin
/// (`flutter_activity_recognition`, wrapping Android's
/// ActivityRecognitionClient and iOS's CMMotionActivityManager) can be
/// swapped or removed without the engine ever importing plugin types — see
/// docs/AUTO_ATTENDANCE_DESIGN.md section 10.
///
/// Every implementation MUST degrade gracefully: if the permission is
/// denied, the plugin is unavailable, or a read fails/times out, return
/// [DetectionActivity.unknown] rather than throwing. The confidence engine
/// treats `unknown` as "this evidence type is unavailable" and renormalizes
/// around the remaining signals (see docs section 4) — it never blocks
/// detection.
abstract class ActivitySignalSource {
  /// Best-effort current activity classification, sampled as a single
  /// bounded "burst" read (see docs section 8, battery strategy) rather
  /// than a long-lived subscription. Never throws.
  Future<DetectionActivity> currentActivity();
}

DetectionActivity _mapActivityType(ActivityType type) {
  // Matched case-insensitively/by substring against the plugin's actual
  // (UPPER_SNAKE_CASE) enum member names — IN_VEHICLE, ON_BICYCLE, RUNNING,
  // STILL, WALKING, UNKNOWN — verified against the installed package
  // source (flutter_activity_recognition 4.0.0).
  final name = type.name.toLowerCase();
  if (name.contains('still') || name.contains('stationary')) {
    return DetectionActivity.stationary;
  }
  if (name.contains('walk')) return DetectionActivity.walking;
  if (name.contains('run')) return DetectionActivity.running;
  if (name.contains('bicycle') || name.contains('cycl')) {
    return DetectionActivity.cycling;
  }
  if (name.contains('vehicle')) return DetectionActivity.vehicle;
  return DetectionActivity.unknown;
}

bool _isPermissionGranted(ActivityPermission permission) {
  return permission.name.toLowerCase().contains('grant');
}

/// [ActivitySignalSource] backed by `flutter_activity_recognition`.
///
/// Android's ActivityRecognitionClient and iOS's CMMotionActivityManager are
/// both push-based (no synchronous "give me the activity right now" API), so
/// each burst read waits for the plugin's next delivered event, bounded by
/// [burstTimeout], and returns `unknown` on timeout rather than blocking the
/// detection engine indefinitely. Each call is independent — there is no
/// persistent subscription kept alive between bursts, consistent with the
/// "no continuous background polling" battery requirement.
class PluginActivitySignalSource implements ActivitySignalSource {
  final Duration burstTimeout;
  bool _permanentlyDenied = false;

  PluginActivitySignalSource({this.burstTimeout = const Duration(seconds: 4)});

  Future<bool> _ensurePermission() async {
    if (_permanentlyDenied) return false;
    try {
      var permission = await FlutterActivityRecognition.instance.checkPermission();
      if (!_isPermissionGranted(permission)) {
        permission = await FlutterActivityRecognition.instance.requestPermission();
      }
      if (!_isPermissionGranted(permission)) {
        _permanentlyDenied = true;
        return false;
      }
      return true;
    } catch (e) {
      LoggerService.instance.error(
        '[AttendanceDetection] activity recognition permission check failed: $e',
        type: LogType.detection,
      );
      return false;
    }
  }

  @override
  Future<DetectionActivity> currentActivity() async {
    try {
      if (!await _ensurePermission()) return DetectionActivity.unknown;
      final activity = await FlutterActivityRecognition.instance.activityStream.first
          .timeout(burstTimeout);
      if (activity.confidence.name.toLowerCase().contains('low')) {
        // Low-confidence readings are noisier than no reading at all.
        return DetectionActivity.unknown;
      }
      return _mapActivityType(activity.type);
    } catch (e) {
      // Timeout, platform exception, or anything else — never let activity
      // recognition failures block attendance detection.
      return DetectionActivity.unknown;
    }
  }
}
