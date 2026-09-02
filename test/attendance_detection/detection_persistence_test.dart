import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:office_log/services/attendance_detection/detection_models.dart';
import 'package:office_log/services/attendance_detection/detection_persistence.dart';
import 'package:office_log/services/attendance_detection/detection_state_machine.dart';

import 'test_helpers.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('officelog_hive_test_');
    Hive.init(tempDir.path);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('save/load round-trips an in-progress episode', () async {
    final persistence = DetectionPersistence();
    const userId = 'user-1';

    final initial = await persistence.load(userId);
    expect(initial.state, AttendanceDetectionState.unknown);

    final withEpisode = DetectionEngineState(
      state: AttendanceDetectionState.possibleArrival,
      episode: [
        obs(timestamp: baseTime, activity: DetectionActivity.walking, distanceMeters: 60),
        obs(
          timestamp: baseTime.add(const Duration(minutes: 2)),
          activity: DetectionActivity.stationary,
          distanceMeters: 40,
        ),
      ],
      episodeAnchor: baseTime,
      nativeDwellSeen: true,
    );

    await persistence.save(userId, withEpisode);
    final reloaded = await persistence.load(userId);

    expect(reloaded.state, AttendanceDetectionState.possibleArrival);
    expect(reloaded.episode.length, 2);
    expect(reloaded.episode.first.activity, DetectionActivity.walking);
    expect(reloaded.episodeAnchor, baseTime);
    expect(reloaded.nativeDwellSeen, isTrue);
  });

  test('load returns initial state for an unknown user (never crashes)', () async {
    final persistence = DetectionPersistence();
    final state = await persistence.load('never-seen-before');
    expect(state.state, AttendanceDetectionState.unknown);
    expect(state.episode, isEmpty);
  });

  test('two users never share persisted state', () async {
    final persistence = DetectionPersistence();
    await persistence.save(
      'user-a',
      DetectionEngineState(
        state: AttendanceDetectionState.atWorkplace,
        episode: const [],
        episodeAnchor: null,
        nativeDwellSeen: false,
      ),
    );

    final userB = await persistence.load('user-b');
    expect(userB.state, AttendanceDetectionState.unknown);
  });

  test('clear resets a user back to initial state', () async {
    final persistence = DetectionPersistence();
    const userId = 'user-1';
    await persistence.save(
      userId,
      DetectionEngineState(
        state: AttendanceDetectionState.atWorkplace,
        episode: const [],
        episodeAnchor: null,
        nativeDwellSeen: false,
      ),
    );
    await persistence.clear(userId);
    final state = await persistence.load(userId);
    expect(state.state, AttendanceDetectionState.unknown);
  });
}
