import 'package:office_log/services/attendance_detection/detection_models.dart';

/// Shared observation builder for detection engine tests. Defaults produce a
/// "good" inside-radius, stationary, high-confidence-supporting sample;
/// override only what a given scenario needs to vary.
DetectionObservation obs({
  required DateTime timestamp,
  DetectionActivity activity = DetectionActivity.unknown,
  double? distanceMeters,
  double? accuracyMeters = 15,
  bool? workplaceNetworkDetected,
  bool? workplaceRegionActive,
  GeofenceTransition? transition,
  bool isMocked = false,
  String source = 'test',
}) {
  return DetectionObservation(
    timestamp: timestamp,
    activity: activity,
    distanceMeters: distanceMeters,
    accuracyMeters: accuracyMeters,
    workplaceNetworkDetected: workplaceNetworkDetected,
    workplaceRegionActive: workplaceRegionActive,
    transition: transition,
    isMocked: isMocked,
    source: source,
  );
}

final DateTime baseTime = DateTime(2026, 9, 2, 9, 0, 0);
