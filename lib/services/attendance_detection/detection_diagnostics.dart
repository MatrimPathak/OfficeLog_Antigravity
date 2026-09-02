import '../logger_service.dart';
import 'detection_models.dart';

/// Structured, privacy-conscious diagnostic logging for the detection
/// engine — the concrete answer to "why did OfficeLog check me in/out at
/// this time?" (docs/AUTO_ATTENDANCE_DESIGN.md section 9).
///
/// Writes through the existing [LoggerService] (`LogType.detection`), which
/// already caps retention at 500 entries — nothing new to build for that.
/// Never logs raw latitude/longitude, only the already-derived distance.
class DetectionDiagnostics {
  static void logObservation(DetectionObservation obs, {String? note}) {
    final parts = <String>[
      'source=${obs.source}',
      if (obs.transition != null) 'transition=${obs.transition!.name}',
      'activity=${obs.activity.name}',
      if (obs.distanceMeters != null)
        'distance=${obs.distanceMeters!.round()}m',
      if (obs.accuracyMeters != null)
        'accuracy=${obs.accuracyMeters!.round()}m',
      if (obs.workplaceNetworkDetected != null)
        'network=${obs.workplaceNetworkDetected! ? "workplace" : "other/none"}',
      if (obs.isMocked) 'MOCKED',
    ];
    if (note != null) parts.add(note);
    LoggerService.instance.info(
      '[AttendanceDetection] ${parts.join(' ')}',
      type: LogType.detection,
    );
  }

  static void logTransition(String summary) {
    LoggerService.instance.info(
      '[AttendanceDetection] $summary',
      type: LogType.detection,
    );
  }

  static void logDecision(AttendanceDecision decision) {
    final evidence = decision.evidence.toMap();
    final evidenceStr = evidence.entries
        .map((e) => '${e.key}:${e.value}')
        .join(', ');
    LoggerService.instance.info(
      '[AttendanceDetection] DECISION ${decision.type.name} '
      'confidence=${decision.confidence.toStringAsFixed(2)} '
      'estimatedTime=${decision.estimatedTimestamp.toIso8601String()} '
      'activity=${decision.activityAtConfirmation.name} '
      'distance=${decision.distanceMetersAtConfirmation?.round()}m '
      'accuracy=${decision.accuracyMetersAtConfirmation?.round()}m '
      'rationale="${decision.timestampRationale}" '
      'evidence={$evidenceStr}',
      type: LogType.detection,
    );
  }

  static void logError(String message) {
    LoggerService.instance.error(
      '[AttendanceDetection] $message',
      type: LogType.detection,
    );
  }
}
