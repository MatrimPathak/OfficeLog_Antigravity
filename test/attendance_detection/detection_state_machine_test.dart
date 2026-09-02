import 'package:flutter_test/flutter_test.dart';
import 'package:office_log/services/attendance_detection/detection_models.dart';
import 'package:office_log/services/attendance_detection/detection_state_machine.dart';

import 'test_helpers.dart';

const radius = 100.0;

void main() {
  const machine = DetectionStateMachine();

  group('Arrival', () {
    test('1. drives past the office — no check-in', () {
      var state = DetectionEngineState.initial;

      final r1 = machine.process(
        current: state,
        observation: obs(
          timestamp: baseTime,
          transition: GeofenceTransition.enter,
          activity: DetectionActivity.vehicle,
          distanceMeters: 80,
        ),
        radiusMeters: radius,
      );
      state = r1.nextState;
      expect(r1.decision, isNull);
      expect(state.state, AttendanceDetectionState.nearWorkplace);

      final r2 = machine.process(
        current: state,
        observation: obs(
          timestamp: baseTime.add(const Duration(seconds: 30)),
          transition: GeofenceTransition.exit,
          activity: DetectionActivity.vehicle,
          distanceMeters: 150,
        ),
        radiusMeters: radius,
      );

      expect(r2.decision, isNull);
      expect(r2.nextState.state, AttendanceDetectionState.unknown);
    });

    test('2. walks into the office — check-in backdated to the first '
        'walking/in-range sample', () {
      var state = DetectionEngineState.initial;

      final o1 = obs(
        timestamp: baseTime,
        transition: GeofenceTransition.enter,
        activity: DetectionActivity.walking,
        distanceMeters: 60,
      );
      final r1 = machine.process(current: state, observation: o1, radiusMeters: radius);
      state = r1.nextState;
      expect(r1.decision, isNull);

      final o2 = obs(
        timestamp: baseTime.add(const Duration(seconds: 90)),
        activity: DetectionActivity.walking,
        distanceMeters: 55,
        workplaceRegionActive: true,
      );
      final r2 = machine.process(current: state, observation: o2, radiusMeters: radius);
      state = r2.nextState;
      expect(r2.decision, isNull, reason: 'not enough dwell time yet');
      expect(state.state, AttendanceDetectionState.possibleArrival);

      final o3 = obs(
        timestamp: baseTime.add(const Duration(minutes: 3, seconds: 10)),
        activity: DetectionActivity.stationary,
        distanceMeters: 50,
        workplaceRegionActive: true,
      );
      final r3 = machine.process(current: state, observation: o3, radiusMeters: radius);

      expect(r3.decision, isNotNull);
      expect(r3.decision!.type, AttendanceDecisionType.checkIn);
      expect(r3.decision!.confidence, greaterThanOrEqualTo(0.72));
      // Backdated to the first individually-supporting sample (o1), not the
      // confirming sample (o3) three minutes later.
      expect(r3.decision!.estimatedTimestamp, o1.timestamp);
      expect(r3.nextState.state, AttendanceDetectionState.atWorkplace);
    });

    test('3. stays outside the office for 30+ minutes — no state change', () {
      var state = DetectionEngineState.initial;
      for (var i = 0; i < 6; i++) {
        final r = machine.process(
          current: state,
          observation: obs(
            timestamp: baseTime.add(Duration(minutes: i * 5)),
            distanceMeters: 400,
            workplaceRegionActive: false,
          ),
          radiusMeters: radius,
        );
        state = r.nextState;
        expect(r.decision, isNull);
      }
      expect(state.state, AttendanceDetectionState.unknown);
    });

    test('4. enters the GPS radius but stays IN_VEHICLE for a while before '
        'actually parking and walking in', () {
      var state = DetectionEngineState.initial;

      final r1 = machine.process(
        current: state,
        observation: obs(
          timestamp: baseTime,
          transition: GeofenceTransition.enter,
          activity: DetectionActivity.vehicle,
          distanceMeters: 85,
        ),
        radiusMeters: radius,
      );
      state = r1.nextState;

      // Still sitting in the vehicle within the radius (e.g. circling for
      // parking) for 40 minutes — activity evidence actively opposes
      // arrival the whole time, so confidence must never cross the
      // threshold on these samples alone.
      for (var i = 1; i <= 8; i++) {
        final r = machine.process(
          current: state,
          observation: obs(
            timestamp: baseTime.add(Duration(minutes: i * 5)),
            activity: DetectionActivity.vehicle,
            distanceMeters: 85,
            workplaceRegionActive: true,
          ),
          radiusMeters: radius,
        );
        state = r.nextState;
        expect(r.decision, isNull, reason: 'still IN_VEHICLE at minute ${i * 5}');
      }
      expect(state.state, AttendanceDetectionState.possibleArrival);

      // Finally parks and walks in.
      final rFinal = machine.process(
        current: state,
        observation: obs(
          timestamp: baseTime.add(const Duration(minutes: 45)),
          activity: DetectionActivity.walking,
          distanceMeters: 40,
          workplaceRegionActive: true,
        ),
        radiusMeters: radius,
      );
      expect(rFinal.decision, isNotNull);
      expect(rFinal.decision!.type, AttendanceDecisionType.checkIn);
      // Backdated only to the first WALKING sample — none of the 40 minutes
      // of vehicle evidence qualifies as arrival-supporting.
      expect(rFinal.decision!.estimatedTimestamp, baseTime.add(const Duration(minutes: 45)));
    });

    test('5. GPS is inaccurate — still checks in via geofence+activity', () {
      var state = DetectionEngineState.initial;

      final r1 = machine.process(
        current: state,
        observation: obs(
          timestamp: baseTime,
          transition: GeofenceTransition.enter,
          activity: DetectionActivity.walking,
          distanceMeters: 70,
          accuracyMeters: 220, // much worse than radius*1.5 = 150
        ),
        radiusMeters: radius,
      );
      state = r1.nextState;

      final r2 = machine.process(
        current: state,
        observation: obs(
          timestamp: baseTime.add(const Duration(minutes: 3, seconds: 5)),
          transition: GeofenceTransition.dwell,
          activity: DetectionActivity.stationary,
          distanceMeters: 65,
          accuracyMeters: 200,
          workplaceRegionActive: true,
        ),
        radiusMeters: radius,
      );

      expect(r2.decision, isNotNull);
      expect(r2.decision!.type, AttendanceDecisionType.checkIn);
      // Location evidence was unavailable (too noisy), not counted at all.
      expect(r2.decision!.evidence.location, isNull);
    });

    test('6. GPS temporarily disappears — still checks in via geofence+activity', () {
      var state = DetectionEngineState.initial;

      final r1 = machine.process(
        current: state,
        observation: obs(
          timestamp: baseTime,
          transition: GeofenceTransition.enter,
          activity: DetectionActivity.walking,
          distanceMeters: 70,
        ),
        radiusMeters: radius,
      );
      state = r1.nextState;

      final r2 = machine.process(
        current: state,
        observation: obs(
          timestamp: baseTime.add(const Duration(minutes: 3, seconds: 5)),
          transition: GeofenceTransition.dwell,
          activity: DetectionActivity.stationary,
          distanceMeters: null, // location fetch failed entirely
          accuracyMeters: null,
          workplaceRegionActive: true,
        ),
        radiusMeters: radius,
      );

      expect(r2.decision, isNotNull);
      expect(r2.decision!.type, AttendanceDecisionType.checkIn);
    });

    test('7. arrives with Wi-Fi unavailable — reaches full confidence anyway', () {
      var state = DetectionEngineState.initial;
      final r1 = machine.process(
        current: state,
        observation: obs(
          timestamp: baseTime,
          transition: GeofenceTransition.enter,
          activity: DetectionActivity.walking,
          distanceMeters: 60,
          workplaceNetworkDetected: null,
        ),
        radiusMeters: radius,
      );
      state = r1.nextState;

      final r2 = machine.process(
        current: state,
        observation: obs(
          timestamp: baseTime.add(const Duration(minutes: 3, seconds: 5)),
          transition: GeofenceTransition.dwell,
          activity: DetectionActivity.stationary,
          distanceMeters: 50,
          workplaceNetworkDetected: null,
          workplaceRegionActive: true,
        ),
        radiusMeters: radius,
      );

      expect(r2.decision, isNotNull);
      expect(r2.decision!.evidence.network, isNull);
      expect(r2.decision!.confidence, greaterThanOrEqualTo(0.72));
    });

    test('8. arrives with activity classification unavailable', () {
      var state = DetectionEngineState.initial;
      final r1 = machine.process(
        current: state,
        observation: obs(
          timestamp: baseTime,
          transition: GeofenceTransition.enter,
          activity: DetectionActivity.unknown,
          distanceMeters: 55,
        ),
        radiusMeters: radius,
      );
      state = r1.nextState;

      final r2 = machine.process(
        current: state,
        observation: obs(
          timestamp: baseTime.add(const Duration(minutes: 3, seconds: 5)),
          transition: GeofenceTransition.dwell,
          activity: DetectionActivity.unknown,
          distanceMeters: 45,
          workplaceRegionActive: true,
        ),
        radiusMeters: radius,
      );

      expect(r2.decision, isNotNull);
      expect(r2.decision!.evidence.activity, isNull);
      expect(r2.decision!.confidence, greaterThanOrEqualTo(0.72));
    });
  });

  group('Departure', () {
    DetectionEngineState atWorkplaceState() => const DetectionEngineState(
      state: AttendanceDetectionState.atWorkplace,
      episode: [],
      episodeAnchor: null,
      nativeDwellSeen: false,
    );

    test('1. leaves desk but remains inside the building — no action', () {
      final r = machine.process(
        current: atWorkplaceState(),
        observation: obs(
          timestamp: baseTime,
          activity: DetectionActivity.walking,
          distanceMeters: 20,
          workplaceRegionActive: true,
        ),
        radiusMeters: radius,
      );
      expect(r.decision, isNull);
      expect(r.nextState.state, AttendanceDetectionState.atWorkplace);
    });

    test('2. leaves the building — check-out fires once evidence accumulates', () {
      var state = atWorkplaceState();

      final r1 = machine.process(
        current: state,
        observation: obs(
          timestamp: baseTime,
          transition: GeofenceTransition.exit,
          activity: DetectionActivity.walking,
          distanceMeters: 130,
        ),
        radiusMeters: radius,
      );
      state = r1.nextState;
      expect(state.state, AttendanceDetectionState.possibleDeparture);

      final r2 = machine.process(
        current: state,
        observation: obs(
          timestamp: baseTime.add(const Duration(minutes: 2)),
          activity: DetectionActivity.walking,
          distanceMeters: 200,
          workplaceRegionActive: false,
        ),
        radiusMeters: radius,
      );

      expect(r2.decision, isNotNull);
      expect(r2.decision!.type, AttendanceDecisionType.checkOut);
      expect(r2.nextState.state, AttendanceDetectionState.awayFromWorkplace);
    });

    test('3. remains just outside the radius — no check-out from jitter alone', () {
      var state = atWorkplaceState();
      final r1 = machine.process(
        current: state,
        observation: obs(
          timestamp: baseTime,
          transition: GeofenceTransition.exit,
          activity: DetectionActivity.unknown,
          distanceMeters: 105, // just past the 100m radius
        ),
        radiusMeters: radius,
      );
      state = r1.nextState;

      final r2 = machine.process(
        current: state,
        observation: obs(
          timestamp: baseTime.add(const Duration(minutes: 2)),
          activity: DetectionActivity.unknown,
          distanceMeters: 108, // still well inside the 1.15x hysteresis band
          workplaceRegionActive: false,
        ),
        radiusMeters: radius,
      );

      expect(r2.decision, isNull);
    });

    test('4. drives away — check-out fires quickly with strong evidence', () {
      var state = atWorkplaceState();
      final r1 = machine.process(
        current: state,
        observation: obs(
          timestamp: baseTime,
          transition: GeofenceTransition.exit,
          activity: DetectionActivity.vehicle,
          distanceMeters: 300,
        ),
        radiusMeters: radius,
      );
      state = r1.nextState;

      final r2 = machine.process(
        current: state,
        observation: obs(
          timestamp: baseTime.add(const Duration(minutes: 2)),
          activity: DetectionActivity.vehicle,
          distanceMeters: 800,
          workplaceRegionActive: false,
        ),
        radiusMeters: radius,
      );

      expect(r2.decision, isNotNull);
      expect(r2.decision!.type, AttendanceDecisionType.checkOut);
    });

    test('6. Wi-Fi disconnecting temporarily does not by itself force a checkout', () {
      var state = atWorkplaceState();
      final r1 = machine.process(
        current: state,
        observation: obs(
          timestamp: baseTime,
          transition: GeofenceTransition.exit,
          activity: DetectionActivity.unknown,
          distanceMeters: 103,
          workplaceNetworkDetected: false,
        ),
        radiusMeters: radius,
      );
      expect(r1.decision, isNull);
    });

    test('7. user moves around inside the building — departure is cancelled', () {
      var state = atWorkplaceState();
      final r1 = machine.process(
        current: state,
        observation: obs(
          timestamp: baseTime,
          transition: GeofenceTransition.exit,
          activity: DetectionActivity.walking,
          distanceMeters: 130,
        ),
        radiusMeters: radius,
      );
      state = r1.nextState;
      expect(state.state, AttendanceDetectionState.possibleDeparture);

      final r2 = machine.process(
        current: state,
        observation: obs(
          timestamp: baseTime.add(const Duration(minutes: 1)),
          transition: GeofenceTransition.enter,
          activity: DetectionActivity.walking,
          distanceMeters: 20,
        ),
        radiusMeters: radius,
      );

      expect(r2.decision, isNull);
      expect(r2.nextState.state, AttendanceDetectionState.atWorkplace);
    });

    test('8. GPS jitters in/out/in/out around the boundary — no duplicate events', () {
      var state = atWorkplaceState();
      final events = [
        (GeofenceTransition.exit, 130.0),
        (GeofenceTransition.enter, 90.0),
        (GeofenceTransition.exit, 140.0),
        (GeofenceTransition.enter, 85.0),
      ];
      var decisions = 0;
      for (var i = 0; i < events.length; i++) {
        final (transition, distance) = events[i];
        final r = machine.process(
          current: state,
          observation: obs(
            timestamp: baseTime.add(Duration(seconds: i * 20)),
            transition: transition,
            distanceMeters: distance,
          ),
          radiusMeters: radius,
        );
        state = r.nextState;
        if (r.decision != null) decisions++;
      }
      expect(decisions, 0);
      expect(state.state, AttendanceDetectionState.atWorkplace);
    });
  });

  group('Reliability', () {
    test('process restart: state round-trips through toMap/fromMap and resumes identically', () {
      var state = DetectionEngineState.initial;
      final r1 = machine.process(
        current: state,
        observation: obs(
          timestamp: baseTime,
          transition: GeofenceTransition.enter,
          activity: DetectionActivity.walking,
          distanceMeters: 60,
        ),
        radiusMeters: radius,
      );
      state = r1.nextState;

      // Simulate process death + restart: round-trip through persistence's
      // exact serialization format.
      final restored = DetectionEngineState.fromMap(state.toMap());

      final r2 = machine.process(
        current: restored,
        observation: obs(
          timestamp: baseTime.add(const Duration(minutes: 3, seconds: 10)),
          activity: DetectionActivity.stationary,
          distanceMeters: 50,
          workplaceRegionActive: true,
        ),
        radiusMeters: radius,
      );

      expect(r2.decision, isNotNull);
      expect(r2.decision!.type, AttendanceDecisionType.checkIn);
    });

    test('duplicate/replayed ENTER events never produce two check-ins', () {
      var state = DetectionEngineState.initial;
      AttendanceDecision? decision;
      final events = [
        obs(timestamp: baseTime, transition: GeofenceTransition.enter, activity: DetectionActivity.walking, distanceMeters: 60),
        // Same ENTER redelivered by the OS (documented native_geofence quirk).
        obs(timestamp: baseTime.add(const Duration(seconds: 1)), transition: GeofenceTransition.enter, activity: DetectionActivity.walking, distanceMeters: 60),
        obs(timestamp: baseTime.add(const Duration(minutes: 3, seconds: 10)), transition: GeofenceTransition.dwell, activity: DetectionActivity.stationary, distanceMeters: 50, workplaceRegionActive: true),
        // Replay the dwell event again after check-in already committed.
        obs(timestamp: baseTime.add(const Duration(minutes: 3, seconds: 11)), transition: GeofenceTransition.dwell, activity: DetectionActivity.stationary, distanceMeters: 50, workplaceRegionActive: true),
      ];
      var checkIns = 0;
      for (final o in events) {
        final r = machine.process(current: state, observation: o, radiusMeters: radius);
        state = r.nextState;
        if (r.decision != null) {
          decision = r.decision;
          if (decision!.type == AttendanceDecisionType.checkIn) checkIns++;
        }
      }
      expect(checkIns, 1);
      expect(state.state, AttendanceDetectionState.atWorkplace);
    });

    test('day rollover resets a stale in-progress episode', () {
      var state = DetectionEngineState.initial;
      final r1 = machine.process(
        current: state,
        observation: obs(
          timestamp: baseTime,
          transition: GeofenceTransition.enter,
          activity: DetectionActivity.walking,
          distanceMeters: 60,
        ),
        radiusMeters: radius,
      );
      state = r1.nextState;
      expect(state.state, AttendanceDetectionState.nearWorkplace);

      // A new observation the next calendar day, still "inside" — must not
      // silently continue yesterday's episode.
      final nextDay = obs(
        timestamp: baseTime.add(const Duration(days: 1)),
        activity: DetectionActivity.walking,
        distanceMeters: 55,
        workplaceRegionActive: true,
      );
      final r2 = machine.process(current: state, observation: nextDay, radiusMeters: radius);

      // Fresh episode restarted today rather than treating this as the
      // second corroborating sample of yesterday's episode.
      expect(r2.decision, isNull);
      expect(r2.nextState.episode.length, 1);
      expect(r2.nextState.episode.first.timestamp, nextDay.timestamp);
    });

    test('idempotency: replayed EXIT events after checkout never re-emit', () {
      var state = const DetectionEngineState(
        state: AttendanceDetectionState.awayFromWorkplace,
        episode: [],
        episodeAnchor: null,
        nativeDwellSeen: false,
      );
      for (var i = 0; i < 3; i++) {
        final r = machine.process(
          current: state,
          observation: obs(
            timestamp: baseTime.add(Duration(minutes: i)),
            transition: GeofenceTransition.exit,
            distanceMeters: 500,
          ),
          radiusMeters: radius,
        );
        state = r.nextState;
        expect(r.decision, isNull);
      }
      expect(state.state, AttendanceDetectionState.awayFromWorkplace);
    });
  });
}
