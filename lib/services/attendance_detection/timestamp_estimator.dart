import 'confidence_engine.dart';
import 'detection_config.dart';
import 'detection_models.dart';

/// The estimated transition timestamp plus a short, human-readable
/// explanation of how it was derived — never `geofenceEvent.timestamp`.
/// See docs/AUTO_ATTENDANCE_DESIGN.md section 5.
class TimestampEstimate {
  final DateTime timestamp;
  final String rationale;
  const TimestampEstimate({required this.timestamp, required this.rationale});
}

bool _individuallySupportsArrival(
  DetectionObservation obs,
  double radiusMeters,
  DetectionConfig config,
) {
  if (obs.distanceMeters == null) return false;
  if (obs.isMocked) return false;
  final accuracy = obs.accuracyMeters ?? radiusMeters;
  if (accuracy > radiusMeters * 1.5) return false;
  if (obs.distanceMeters! > radiusMeters * config.arrivalProximityFactor) {
    return false;
  }
  return activityArrivalPolarity(obs.activity) >= 0;
}

bool _individuallyContradictsArrival(
  DetectionObservation obs,
  double radiusMeters,
) {
  if (activityArrivalPolarity(obs.activity) < 0) return true;
  if (obs.distanceMeters != null && obs.distanceMeters! > radiusMeters * 1.5) {
    return true;
  }
  return false;
}

bool _individuallySupportsDeparture(
  DetectionObservation obs,
  double radiusMeters,
  DetectionConfig config,
) {
  if (obs.isMocked) return false;
  final activitySupports = activityDeparturePolarity(obs.activity) > 0;
  final locationSupports =
      obs.distanceMeters != null &&
      obs.distanceMeters! >= radiusMeters * config.departureHysteresisFactor;
  return activitySupports || locationSupports;
}

bool _individuallyContradictsDeparture(
  DetectionObservation obs,
  double radiusMeters,
) {
  if (activityDeparturePolarity(obs.activity) < 0) return true;
  if (obs.distanceMeters != null && obs.distanceMeters! < radiusMeters * 0.5) {
    return true;
  }
  return false;
}

String _formatTime(DateTime t) {
  final h = t.hour.toString().padLeft(2, '0');
  final m = t.minute.toString().padLeft(2, '0');
  final s = t.second.toString().padLeft(2, '0');
  return '$h:$m:$s';
}

/// Picks the earliest observation in [episode] that already looked
/// arrival-supporting on its own and is not contradicted by any later
/// observation before the confirming (last) sample. Falls back to the
/// confirming sample itself when no earlier one qualifies — the engine never
/// invents precision the signals don't support.
TimestampEstimate estimateArrivalTimestamp({
  required List<DetectionObservation> episode,
  required double radiusMeters,
  required DetectionConfig config,
}) {
  assert(episode.isNotEmpty);
  final confirmation = episode.last;

  for (var i = 0; i < episode.length; i++) {
    final candidate = episode[i];
    if (!_individuallySupportsArrival(candidate, radiusMeters, config)) {
      continue;
    }
    var contradicted = false;
    for (var j = i + 1; j < episode.length; j++) {
      if (_individuallyContradictsArrival(episode[j], radiusMeters)) {
        contradicted = true;
        break;
      }
    }
    if (contradicted) continue;

    final backdated = confirmation.timestamp.difference(candidate.timestamp);
    if (candidate == confirmation) {
      return TimestampEstimate(
        timestamp: candidate.timestamp,
        rationale:
            'confirming sample at ${_formatTime(candidate.timestamp)} '
            'already carried the strongest evidence available; no earlier '
            'independent sample qualified',
      );
    }
    return TimestampEstimate(
      timestamp: candidate.timestamp,
      rationale:
          'backdated ${backdated.inMinutes}m from confirmation to first '
          '${candidate.activity.name}+in-range sample at '
          '${_formatTime(candidate.timestamp)} (source=${candidate.source}); '
          'no contradicting sample in between',
    );
  }

  return TimestampEstimate(
    timestamp: confirmation.timestamp,
    rationale:
        'no individual sample in the episode independently qualified as '
        'arrival-supporting; using the confirming sample at '
        '${_formatTime(confirmation.timestamp)}',
  );
}

/// Symmetric to [estimateArrivalTimestamp] for departure.
TimestampEstimate estimateDepartureTimestamp({
  required List<DetectionObservation> episode,
  required double radiusMeters,
  required DetectionConfig config,
}) {
  assert(episode.isNotEmpty);
  final confirmation = episode.last;

  for (var i = 0; i < episode.length; i++) {
    final candidate = episode[i];
    if (!_individuallySupportsDeparture(candidate, radiusMeters, config)) {
      continue;
    }
    var contradicted = false;
    for (var j = i + 1; j < episode.length; j++) {
      if (_individuallyContradictsDeparture(episode[j], radiusMeters)) {
        contradicted = true;
        break;
      }
    }
    if (contradicted) continue;

    final backdated = confirmation.timestamp.difference(candidate.timestamp);
    if (candidate == confirmation) {
      return TimestampEstimate(
        timestamp: candidate.timestamp,
        rationale:
            'confirming sample at ${_formatTime(candidate.timestamp)} '
            'already carried the strongest evidence available; no earlier '
            'independent sample qualified',
      );
    }
    return TimestampEstimate(
      timestamp: candidate.timestamp,
      rationale:
          'backdated ${backdated.inMinutes}m from confirmation to first '
          '${candidate.activity.name}+departing sample at '
          '${_formatTime(candidate.timestamp)} (source=${candidate.source}); '
          'no contradicting sample in between',
    );
  }

  return TimestampEstimate(
    timestamp: confirmation.timestamp,
    rationale:
        'no individual sample in the episode independently qualified as '
        'departure-supporting; using the confirming sample at '
        '${_formatTime(confirmation.timestamp)}',
  );
}
