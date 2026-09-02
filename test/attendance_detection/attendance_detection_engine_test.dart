import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:office_log/services/attendance_detection/attendance_detection_engine.dart';
import 'package:office_log/services/attendance_detection/confirmation_scheduler.dart';
import 'package:office_log/services/attendance_detection/detection_config.dart';
import 'package:office_log/services/attendance_detection/detection_models.dart';
import 'package:office_log/services/attendance_detection/signal_sources/activity_signal_source.dart';
import 'package:office_log/services/attendance_detection/signal_sources/location_signal_source.dart';
import 'package:office_log/services/attendance_detection/signal_sources/network_signal_source.dart';

class _FakeLocationSignalSource extends LocationSignalSource {
  LocationSample sample;
  _FakeLocationSignalSource(this.sample);

  @override
  Future<LocationSample> fetchSample({
    required double officeLat,
    required double officeLng,
  }) async => sample;
}

class _FakeActivitySignalSource implements ActivitySignalSource {
  DetectionActivity activity;
  _FakeActivitySignalSource(this.activity);

  @override
  Future<DetectionActivity> currentActivity() async => activity;
}

class _FakeNetworkSignalSource implements NetworkSignalSource {
  @override
  Future<bool?> isConnectedToWorkplaceNetwork() async => null;
}

class _FakeConfirmationScheduler implements ConfirmationScheduler {
  int scheduleCount = 0;
  int cancelCount = 0;
  Duration? lastDelay;

  @override
  Future<void> scheduleConfirmation({required Duration delay}) async {
    scheduleCount++;
    lastDelay = delay;
  }

  @override
  Future<void> cancelConfirmation() async {
    cancelCount++;
  }
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('officelog_engine_test_');
    Hive.init(tempDir.path);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('an in-progress episode schedules a confirming re-check; a resolved '
      'decision cancels it', () async {
    final location = _FakeLocationSignalSource(
      const LocationSample(distanceMeters: 60, accuracyMeters: 15),
    );
    final activity = _FakeActivitySignalSource(DetectionActivity.walking);
    final scheduler = _FakeConfirmationScheduler();
    var now = DateTime(2026, 9, 2, 9, 0, 0);

    final engine = AttendanceDetectionEngine(
      activitySource: activity,
      networkSource: _FakeNetworkSignalSource(),
      locationSource: location,
      confirmationScheduler: scheduler,
      clock: () => now,
    );

    // First ENTER: single sample, awaiting corroboration — in progress.
    final d1 = await engine.processGeofenceEvent(
      userId: 'user-1',
      transition: GeofenceTransition.enter,
      officeLat: 0,
      officeLng: 0,
      radiusMeters: 100,
      allowMockLocation: false,
    );
    expect(d1, isNull);
    expect(scheduler.scheduleCount, 1);
    expect(scheduler.lastDelay, DetectionConfig.defaultConfig.softDwellDuration);
    expect(scheduler.cancelCount, 0);

    // Confirming sample (what the scheduled re-check would supply) arrives
    // after the soft-dwell window, with stationary activity: resolves to a
    // check-in.
    now = now.add(const Duration(minutes: 3, seconds: 10));
    activity.activity = DetectionActivity.stationary;
    location.sample = const LocationSample(distanceMeters: 50, accuracyMeters: 15);

    final d2 = await engine.processForegroundCheck(
      userId: 'user-1',
      officeLat: 0,
      officeLng: 0,
      radiusMeters: 100,
      allowMockLocation: false,
    );

    expect(d2, isNotNull);
    expect(d2!.type, AttendanceDecisionType.checkIn);
    // Resolved to AT_WORKPLACE: the pending confirmation must be cancelled,
    // not left to keep firing uselessly.
    expect(scheduler.cancelCount, 1);
  });

  test('a discarded (pass-by) episode also cancels any pending confirmation', () async {
    final location = _FakeLocationSignalSource(
      const LocationSample(distanceMeters: 80, accuracyMeters: 15),
    );
    final scheduler = _FakeConfirmationScheduler();

    final engine = AttendanceDetectionEngine(
      activitySource: _FakeActivitySignalSource(DetectionActivity.vehicle),
      networkSource: _FakeNetworkSignalSource(),
      locationSource: location,
      confirmationScheduler: scheduler,
    );

    await engine.processGeofenceEvent(
      userId: 'user-2',
      transition: GeofenceTransition.enter,
      officeLat: 0,
      officeLng: 0,
      radiusMeters: 100,
      allowMockLocation: false,
    );
    expect(scheduler.scheduleCount, 1);

    location.sample = const LocationSample(distanceMeters: 300, accuracyMeters: 15);
    final decision = await engine.processGeofenceEvent(
      userId: 'user-2',
      transition: GeofenceTransition.exit,
      officeLat: 0,
      officeLng: 0,
      radiusMeters: 100,
      allowMockLocation: false,
    );

    expect(decision, isNull);
    expect(scheduler.cancelCount, 1);
  });
}
