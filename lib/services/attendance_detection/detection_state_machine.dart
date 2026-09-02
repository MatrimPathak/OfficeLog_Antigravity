import 'confidence_engine.dart';
import 'detection_config.dart';
import 'detection_models.dart';
import 'timestamp_estimator.dart';

/// Persisted state for one user's detection episode. This is the entire
/// object round-tripped through [DetectionPersistence] between OS-delivered
/// wake-ups; see docs/AUTO_ATTENDANCE_DESIGN.md section 7.
class DetectionEngineState {
  final AttendanceDetectionState state;
  final List<DetectionObservation> episode;
  final DateTime? episodeAnchor;
  final bool nativeDwellSeen;

  const DetectionEngineState({
    required this.state,
    required this.episode,
    required this.episodeAnchor,
    required this.nativeDwellSeen,
  });

  static const DetectionEngineState initial = DetectionEngineState(
    state: AttendanceDetectionState.unknown,
    episode: [],
    episodeAnchor: null,
    nativeDwellSeen: false,
  );

  DetectionEngineState copyWith({
    AttendanceDetectionState? state,
    List<DetectionObservation>? episode,
    DateTime? episodeAnchor,
    bool clearAnchor = false,
    bool? nativeDwellSeen,
  }) {
    return DetectionEngineState(
      state: state ?? this.state,
      episode: episode ?? this.episode,
      episodeAnchor: clearAnchor ? null : (episodeAnchor ?? this.episodeAnchor),
      nativeDwellSeen: nativeDwellSeen ?? this.nativeDwellSeen,
    );
  }

  Map<String, dynamic> toMap() => {
    'state': state.name,
    'episode': episode.map((o) => o.toMap()).toList(),
    'episodeAnchor': episodeAnchor?.toIso8601String(),
    'nativeDwellSeen': nativeDwellSeen,
  };

  factory DetectionEngineState.fromMap(Map<dynamic, dynamic> map) {
    return DetectionEngineState(
      state: AttendanceDetectionState.values.firstWhere(
        (e) => e.name == map['state'],
        orElse: () => AttendanceDetectionState.unknown,
      ),
      episode: map['episode'] != null
          ? (map['episode'] as List)
                .map((o) => DetectionObservation.fromMap(o as Map))
                .toList()
          : <DetectionObservation>[],
      episodeAnchor: map['episodeAnchor'] != null
          ? DateTime.parse(map['episodeAnchor'] as String)
          : null,
      nativeDwellSeen: map['nativeDwellSeen'] as bool? ?? false,
    );
  }
}

/// Result of feeding one observation into the state machine.
class StateMachineResult {
  final DetectionEngineState nextState;
  final AttendanceDecision? decision;
  final String diagnosticSummary;

  const StateMachineResult({
    required this.nextState,
    required this.decision,
    required this.diagnosticSummary,
  });
}

bool _isSameLocalDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Pure (no I/O) attendance detection state machine. All persistence and
/// platform access happens outside this class — see
/// docs/AUTO_ATTENDANCE_DESIGN.md sections 2 and 7.
class DetectionStateMachine {
  final DetectionConfig config;

  const DetectionStateMachine({this.config = DetectionConfig.defaultConfig});

  List<DetectionObservation> _appendBounded(
    List<DetectionObservation> episode,
    DetectionObservation observation,
  ) {
    final next = [...episode, observation];
    final cutoff = observation.timestamp.subtract(config.maxEpisodeAge);
    final trimmedByAge = next.where((o) => o.timestamp.isAfter(cutoff)).toList();
    if (trimmedByAge.length <= config.maxEpisodeObservations) return trimmedByAge;
    return trimmedByAge.sublist(trimmedByAge.length - config.maxEpisodeObservations);
  }

  bool _isInside(DetectionObservation obs, double radiusMeters) {
    if (obs.transition == GeofenceTransition.enter ||
        obs.transition == GeofenceTransition.dwell) {
      return true;
    }
    if (obs.transition == GeofenceTransition.exit) return false;
    if (obs.workplaceRegionActive != null) return obs.workplaceRegionActive!;
    if (obs.distanceMeters != null) return obs.distanceMeters! <= radiusMeters;
    // No positional information at all — assume no change to avoid acting on
    // nothing (e.g. an activity-only sample with no location fix).
    return obs.workplaceRegionActive ?? false;
  }

  /// Feeds one normalized [observation] through the state machine.
  ///
  /// [historicalSupportsArrivalNow] / [historicalSupportsDepartureNow] are
  /// optional low-weight tie-breakers computed by the caller from prior
  /// logged attendance (see docs section 4, HistoricalEvidence) — pass null
  /// when unavailable.
  StateMachineResult process({
    required DetectionEngineState current,
    required DetectionObservation observation,
    required double radiusMeters,
    bool? historicalSupportsArrivalNow,
    bool? historicalSupportsDepartureNow,
  }) {
    var state = current;

    // Day rollover: don't let a stale in-progress episode from a previous
    // calendar day silently influence today.
    if (state.episodeAnchor != null &&
        !_isSameLocalDay(state.episodeAnchor!, observation.timestamp) &&
        state.state != AttendanceDetectionState.unknown &&
        state.state != AttendanceDetectionState.awayFromWorkplace) {
      state = DetectionEngineState.initial;
    }

    final inside = _isInside(observation, radiusMeters);

    switch (state.state) {
      case AttendanceDetectionState.unknown:
      case AttendanceDetectionState.awayFromWorkplace:
        if (!inside) {
          return StateMachineResult(
            nextState: state.state == AttendanceDetectionState.awayFromWorkplace
                ? state
                : state.copyWith(state: AttendanceDetectionState.unknown),
            decision: null,
            diagnosticSummary: 'no workplace signal, remaining ${state.state.name}',
          );
        }
        final started = DetectionEngineState(
          state: AttendanceDetectionState.nearWorkplace,
          episode: [observation],
          episodeAnchor: observation.timestamp,
          nativeDwellSeen: observation.transition == GeofenceTransition.dwell,
        );
        return StateMachineResult(
          nextState: started,
          decision: null,
          diagnosticSummary: 'entered workplace vicinity, starting new episode',
        );

      case AttendanceDetectionState.nearWorkplace:
        final episode = _appendBounded(state.episode, observation);
        final dwellSeen =
            state.nativeDwellSeen || observation.transition == GeofenceTransition.dwell;

        if (!inside) {
          final elapsed = observation.timestamp.difference(state.episodeAnchor!);
          if (!dwellSeen && elapsed <= config.passByGraceDuration) {
            return StateMachineResult(
              nextState: DetectionEngineState.initial,
              decision: null,
              diagnosticSummary:
                  'exited within ${config.passByGraceDuration.inMinutes}m of '
                  'entry with no dwell evidence — treating as pass-by, '
                  'discarding episode',
            );
          }
          return StateMachineResult(
            nextState: DetectionEngineState.initial,
            decision: null,
            diagnosticSummary:
                'exited before enough evidence accumulated, discarding episode',
          );
        }

        if (episode.length < 2) {
          // Only one inside sample so far — wait for a second, independent
          // corroborating signal before evaluating confidence at all.
          return StateMachineResult(
            nextState: state.copyWith(episode: episode, nativeDwellSeen: dwellSeen),
            decision: null,
            diagnosticSummary: 'first inside sample recorded, awaiting corroboration',
          );
        }

        return _evaluateArrival(
          state.copyWith(
            state: AttendanceDetectionState.possibleArrival,
            episode: episode,
            nativeDwellSeen: dwellSeen,
          ),
          radiusMeters,
          historicalSupportsArrivalNow,
        );

      case AttendanceDetectionState.possibleArrival:
        final episode = _appendBounded(state.episode, observation);
        final dwellSeen =
            state.nativeDwellSeen || observation.transition == GeofenceTransition.dwell;
        final withEvidence = state.copyWith(episode: episode, nativeDwellSeen: dwellSeen);

        if (!inside) {
          final elapsed = observation.timestamp.difference(state.episodeAnchor!);
          final result = computeArrivalConfidence(
            episode: episode,
            radiusMeters: radiusMeters,
            firstEnterTimestamp: state.episodeAnchor!,
            nativeDwellSeen: dwellSeen,
            config: config,
            historicalSupportsNow: historicalSupportsArrivalNow,
          );
          if (!dwellSeen && elapsed <= config.passByGraceDuration) {
            return StateMachineResult(
              nextState: DetectionEngineState.initial,
              decision: null,
              diagnosticSummary:
                  'exited within pass-by grace window with no dwell evidence '
                  '(confidence was ${result.confidence.toStringAsFixed(2)}) — discarding',
            );
          }
          if (result.confidence < config.arrivalContinueThreshold) {
            return StateMachineResult(
              nextState: DetectionEngineState.initial,
              decision: null,
              diagnosticSummary:
                  'exited with low confidence (${result.confidence.toStringAsFixed(2)}), discarding episode',
            );
          }
          // Keep the accumulated evidence open in case of a quick re-entry
          // (GPS jitter at the boundary) rather than throwing it away.
          return StateMachineResult(
            nextState: withEvidence.copyWith(state: AttendanceDetectionState.nearWorkplace),
            decision: null,
            diagnosticSummary:
                'exited with borderline confidence (${result.confidence.toStringAsFixed(2)}), '
                'keeping episode open for possible re-entry',
          );
        }

        return _evaluateArrival(withEvidence, radiusMeters, historicalSupportsArrivalNow);

      case AttendanceDetectionState.atWorkplace:
        if (inside) {
          return StateMachineResult(
            nextState: state,
            decision: null,
            diagnosticSummary: 'still inside workplace, no action',
          );
        }
        final departureStart = state.copyWith(
          state: AttendanceDetectionState.possibleDeparture,
          episode: [observation],
          episodeAnchor: observation.timestamp,
        );
        return _evaluateDeparture(departureStart, radiusMeters, historicalSupportsDepartureNow);

      case AttendanceDetectionState.possibleDeparture:
        if (inside) {
          // Re-entry while still evaluating departure: the "moved to another
          // floor" / boundary-jitter case. Never a duplicate check-out here
          // because none has been committed yet.
          return StateMachineResult(
            nextState: state.copyWith(
              state: AttendanceDetectionState.atWorkplace,
              episode: const [],
              clearAnchor: true,
              nativeDwellSeen: false,
            ),
            decision: null,
            diagnosticSummary: 're-entered workplace before departure confirmed, cancelling',
          );
        }
        final episode = _appendBounded(state.episode, observation);
        return _evaluateDeparture(
          state.copyWith(episode: episode),
          radiusMeters,
          historicalSupportsDepartureNow,
        );
    }
  }

  StateMachineResult _evaluateArrival(
    DetectionEngineState state,
    double radiusMeters,
    bool? historicalSupportsNow,
  ) {
    final result = computeArrivalConfidence(
      episode: state.episode,
      radiusMeters: radiusMeters,
      firstEnterTimestamp: state.episodeAnchor!,
      nativeDwellSeen: state.nativeDwellSeen,
      config: config,
      historicalSupportsNow: historicalSupportsNow,
    );

    if (result.confidence >= config.arrivalHighThreshold) {
      final estimate = estimateArrivalTimestamp(
        episode: state.episode,
        radiusMeters: radiusMeters,
        config: config,
      );
      final confirmation = state.episode.last;
      final decision = AttendanceDecision(
        type: AttendanceDecisionType.checkIn,
        estimatedTimestamp: estimate.timestamp,
        confidence: result.confidence,
        evidence: result.evidence,
        timestampRationale: estimate.rationale,
        distanceMetersAtConfirmation: confirmation.distanceMeters,
        accuracyMetersAtConfirmation: confirmation.accuracyMeters,
        activityAtConfirmation: confirmation.activity,
      );
      return StateMachineResult(
        nextState: const DetectionEngineState(
          state: AttendanceDetectionState.atWorkplace,
          episode: [],
          episodeAnchor: null,
          nativeDwellSeen: false,
        ),
        decision: decision,
        diagnosticSummary:
            'arrival confidence ${result.confidence.toStringAsFixed(2)} >= threshold, checking in',
      );
    }

    return StateMachineResult(
      nextState: state,
      decision: null,
      diagnosticSummary:
          'possible arrival, confidence ${result.confidence.toStringAsFixed(2)}, continuing to collect evidence',
    );
  }

  StateMachineResult _evaluateDeparture(
    DetectionEngineState state,
    double radiusMeters,
    bool? historicalSupportsNow,
  ) {
    final result = computeDepartureConfidence(
      episode: state.episode,
      radiusMeters: radiusMeters,
      firstExitTimestamp: state.episodeAnchor!,
      config: config,
      historicalSupportsNow: historicalSupportsNow,
    );

    if (result.confidence >= config.departureHighThreshold) {
      final estimate = estimateDepartureTimestamp(
        episode: state.episode,
        radiusMeters: radiusMeters,
        config: config,
      );
      final confirmation = state.episode.last;
      final decision = AttendanceDecision(
        type: AttendanceDecisionType.checkOut,
        estimatedTimestamp: estimate.timestamp,
        confidence: result.confidence,
        evidence: result.evidence,
        timestampRationale: estimate.rationale,
        distanceMetersAtConfirmation: confirmation.distanceMeters,
        accuracyMetersAtConfirmation: confirmation.accuracyMeters,
        activityAtConfirmation: confirmation.activity,
      );
      return StateMachineResult(
        nextState: const DetectionEngineState(
          state: AttendanceDetectionState.awayFromWorkplace,
          episode: [],
          episodeAnchor: null,
          nativeDwellSeen: false,
        ),
        decision: decision,
        diagnosticSummary:
            'departure confidence ${result.confidence.toStringAsFixed(2)} >= threshold, checking out',
      );
    }

    return StateMachineResult(
      nextState: state,
      decision: null,
      diagnosticSummary:
          'possible departure, confidence ${result.confidence.toStringAsFixed(2)}, continuing to collect evidence',
    );
  }
}
