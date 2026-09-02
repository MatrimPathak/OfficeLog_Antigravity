import 'package:flutter_test/flutter_test.dart';
import 'package:office_log/services/attendance_detection/detection_config.dart';
import 'package:office_log/services/attendance_detection/detection_models.dart';
import 'package:office_log/services/attendance_detection/timestamp_estimator.dart';

import 'test_helpers.dart';

const radius = 100.0;
const config = DetectionConfig.defaultConfig;

void main() {
  group('estimateArrivalTimestamp', () {
    test('backdates to the earliest independently-supporting sample', () {
      final o1 = obs(timestamp: baseTime, activity: DetectionActivity.walking, distanceMeters: 60);
      final o2 = obs(
        timestamp: baseTime.add(const Duration(minutes: 1)),
        activity: DetectionActivity.walking,
        distanceMeters: 55,
      );
      final o3 = obs(
        timestamp: baseTime.add(const Duration(minutes: 3)),
        activity: DetectionActivity.stationary,
        distanceMeters: 50,
      );

      final estimate = estimateArrivalTimestamp(
        episode: [o1, o2, o3],
        radiusMeters: radius,
        config: config,
      );

      expect(estimate.timestamp, o1.timestamp);
      expect(estimate.rationale, contains('backdated'));
    });

    test('does not backdate past a contradicting sample', () {
      final o1 = obs(timestamp: baseTime, activity: DetectionActivity.walking, distanceMeters: 60);
      // A vehicle reading in between contradicts o1 as evidence of a
      // continuous arrival — the estimator must not backdate through it.
      final o2 = obs(
        timestamp: baseTime.add(const Duration(minutes: 1)),
        activity: DetectionActivity.vehicle,
        distanceMeters: 200,
      );
      final o3 = obs(
        timestamp: baseTime.add(const Duration(minutes: 3)),
        activity: DetectionActivity.stationary,
        distanceMeters: 50,
      );

      final estimate = estimateArrivalTimestamp(
        episode: [o1, o2, o3],
        radiusMeters: radius,
        config: config,
      );

      expect(estimate.timestamp, isNot(o1.timestamp));
      expect(estimate.timestamp, o3.timestamp);
    });

    test('falls back to the confirming sample when nothing earlier qualifies', () {
      final o1 = obs(timestamp: baseTime, activity: DetectionActivity.vehicle, distanceMeters: 300);
      final o2 = obs(
        timestamp: baseTime.add(const Duration(minutes: 3)),
        activity: DetectionActivity.stationary,
        distanceMeters: 50,
      );

      final estimate = estimateArrivalTimestamp(
        episode: [o1, o2],
        radiusMeters: radius,
        config: config,
      );

      expect(estimate.timestamp, o2.timestamp);
      expect(estimate.rationale, contains('no earlier'));
    });
  });

  group('estimateDepartureTimestamp', () {
    test('backdates to the first walking-away sample, not the confirmation', () {
      final o1 = obs(timestamp: baseTime, activity: DetectionActivity.walking, distanceMeters: 60);
      final o2 = obs(
        timestamp: baseTime.add(const Duration(minutes: 5)),
        activity: DetectionActivity.walking,
        distanceMeters: 250,
      );

      final estimate = estimateDepartureTimestamp(
        episode: [o1, o2],
        radiusMeters: radius,
        config: config,
      );

      expect(estimate.timestamp, o1.timestamp);
    });
  });
}
