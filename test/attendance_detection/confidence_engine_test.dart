import 'package:flutter_test/flutter_test.dart';
import 'package:office_log/services/attendance_detection/confidence_engine.dart';
import 'package:office_log/services/attendance_detection/detection_config.dart';
import 'package:office_log/services/attendance_detection/detection_models.dart';

import 'test_helpers.dart';

const radius = 100.0;
const config = DetectionConfig.defaultConfig;

void main() {
  group('computeArrivalConfidence', () {
    test('renormalizes when network AND activity are both unavailable, '
        'still reaching full confidence from geofence+location+temporal', () {
      final episode = [
        obs(timestamp: baseTime, transition: GeofenceTransition.enter, distanceMeters: 50),
        obs(
          timestamp: baseTime.add(const Duration(minutes: 4)),
          transition: GeofenceTransition.dwell,
          distanceMeters: 45,
        ),
      ];
      final result = computeArrivalConfidence(
        episode: episode,
        radiusMeters: radius,
        firstEnterTimestamp: baseTime,
        nativeDwellSeen: true,
        config: config,
      );
      expect(result.evidence.network, isNull);
      expect(result.evidence.activity, isNull);
      expect(result.confidence, closeTo(1.0, 0.001));
    });

    test('vehicle activity actively opposes arrival (not merely unavailable)', () {
      final episode = [
        obs(timestamp: baseTime, activity: DetectionActivity.vehicle, distanceMeters: 50),
        obs(
          timestamp: baseTime.add(const Duration(minutes: 4)),
          activity: DetectionActivity.vehicle,
          distanceMeters: 45,
        ),
      ];
      final result = computeArrivalConfidence(
        episode: episode,
        radiusMeters: radius,
        firstEnterTimestamp: baseTime,
        nativeDwellSeen: true,
        config: config,
      );
      expect(result.evidence.activity, isFalse);
      expect(result.confidence, lessThan(config.arrivalHighThreshold));
    });

    test('poor GPS accuracy is excluded (unavailable), not counted negative', () {
      final episode = [
        obs(
          timestamp: baseTime,
          activity: DetectionActivity.stationary,
          distanceMeters: 50,
          accuracyMeters: 500,
        ),
      ];
      final result = computeArrivalConfidence(
        episode: episode,
        radiusMeters: radius,
        firstEnterTimestamp: baseTime,
        nativeDwellSeen: true,
        config: config,
      );
      expect(result.evidence.location, isNull);
    });

    test('mocked location counts as negative evidence, not unavailable', () {
      final episode = [
        obs(
          timestamp: baseTime,
          activity: DetectionActivity.stationary,
          distanceMeters: 50,
          isMocked: true,
        ),
      ];
      final result = computeArrivalConfidence(
        episode: episode,
        radiusMeters: radius,
        firstEnterTimestamp: baseTime,
        nativeDwellSeen: true,
        config: config,
      );
      expect(result.evidence.location, isFalse);
    });

    test('empty episode yields zero confidence, not an error', () {
      final result = computeArrivalConfidence(
        episode: const [],
        radiusMeters: radius,
        firstEnterTimestamp: baseTime,
        nativeDwellSeen: false,
        config: config,
      );
      expect(result.confidence, 0);
    });
  });

  group('computeDepartureConfidence', () {
    test('losing the workplace network supports departure', () {
      final episode = [
        obs(
          timestamp: baseTime,
          distanceMeters: 150,
          workplaceNetworkDetected: false,
        ),
        obs(
          timestamp: baseTime.add(const Duration(minutes: 3)),
          distanceMeters: 200,
          workplaceNetworkDetected: false,
        ),
      ];
      final result = computeDepartureConfidence(
        episode: episode,
        radiusMeters: radius,
        firstExitTimestamp: baseTime,
        config: config,
      );
      expect(result.evidence.network, isTrue);
    });

    test('still connected to the workplace network opposes departure', () {
      final episode = [
        obs(
          timestamp: baseTime,
          distanceMeters: 150,
          workplaceNetworkDetected: true,
        ),
      ];
      final result = computeDepartureConfidence(
        episode: episode,
        radiusMeters: radius,
        firstExitTimestamp: baseTime,
        config: config,
      );
      expect(result.evidence.network, isFalse);
    });
  });
}
