import 'detection_config.dart';
import 'detection_models.dart';

/// Result of scoring an episode's observation history against arrival or
/// departure evidence. See docs/AUTO_ATTENDANCE_DESIGN.md section 4.
class ConfidenceResult {
  final double confidence; // in [0, 1]
  final DetectionEvidence evidence;

  const ConfidenceResult({required this.confidence, required this.evidence});
}

/// How strongly an activity classification supports *arrival* (positive) or
/// opposes it (negative). Used with inverted sign for departure.
double activityArrivalPolarity(DetectionActivity activity) {
  switch (activity) {
    case DetectionActivity.stationary:
      return 1.0;
    case DetectionActivity.walking:
      return 1.0;
    case DetectionActivity.running:
      return 0.5;
    case DetectionActivity.cycling:
      return 0.3;
    case DetectionActivity.vehicle:
      return -1.0;
    case DetectionActivity.unknown:
      return 0.0;
  }
}

double activityDeparturePolarity(DetectionActivity activity) {
  switch (activity) {
    case DetectionActivity.vehicle:
      return 1.0;
    case DetectionActivity.walking:
      return 0.8;
    case DetectionActivity.running:
      return 0.6;
    case DetectionActivity.cycling:
      return 0.6;
    case DetectionActivity.stationary:
      return -1.0;
    case DetectionActivity.unknown:
      return 0.0;
  }
}

/// A weighted, independently-optional evidence contribution. `supported` is
/// null when this evidence type is unavailable for the episode (e.g. no
/// activity permission, no Wi-Fi signal) and is excluded from normalization
/// entirely rather than counted against confidence — this is what makes the
/// engine work without Wi-Fi and degrade gracefully without activity
/// permission.
class _WeightedEvidence {
  final double weight;
  final bool? supported;
  const _WeightedEvidence(this.weight, this.supported);
}

double _aggregate(List<_WeightedEvidence> items) {
  double weightSum = 0;
  double scoreSum = 0;
  for (final item in items) {
    if (item.supported == null) continue;
    weightSum += item.weight;
    scoreSum += item.weight * (item.supported! ? 1.0 : 0.0);
  }
  if (weightSum == 0) return 0.0;
  return scoreSum / weightSum;
}

/// Most recent observation with a non-null [distanceMeters], if any.
DetectionObservation? _latestWithDistance(List<DetectionObservation> episode) {
  for (final obs in episode.reversed) {
    if (obs.distanceMeters != null) return obs;
  }
  return null;
}

/// Most recent observation with a known (non-unknown) activity, if any.
DetectionObservation? _latestWithActivity(List<DetectionObservation> episode) {
  for (final obs in episode.reversed) {
    if (obs.activity != DetectionActivity.unknown) return obs;
  }
  return null;
}

/// Most recent observation carrying a network signal, if any.
DetectionObservation? _latestWithNetwork(List<DetectionObservation> episode) {
  for (final obs in episode.reversed) {
    if (obs.workplaceNetworkDetected != null) return obs;
  }
  return null;
}

/// Location evidence for arrival, or `null` when unavailable — which
/// includes not just "no location sample at all" but also "the most recent
/// sample's accuracy is too poor relative to the radius to say anything
/// meaningful." Treating noisy GPS as *unavailable* (excluded from
/// normalization, see [_aggregate]) rather than as active negative evidence
/// is what lets the engine still reach a confident decision from
/// geofence+activity alone when GPS is inaccurate — see
/// docs/AUTO_ATTENDANCE_DESIGN.md section 4 and the "GPS is inaccurate"
/// test scenario.
bool? _arrivalLocationEvidence(
  List<DetectionObservation> episode,
  double radiusMeters,
  DetectionConfig config,
) {
  final latest = _latestWithDistance(episode);
  if (latest == null) return null;
  final accuracy = latest.accuracyMeters ?? radiusMeters;
  if (accuracy > radiusMeters * 1.5) return null;
  if (latest.isMocked) return false;
  return latest.distanceMeters! <= radiusMeters * config.arrivalProximityFactor;
}

/// Symmetric to [_arrivalLocationEvidence] for departure.
bool? _departureLocationEvidence(
  List<DetectionObservation> episode,
  double radiusMeters,
  DetectionConfig config,
) {
  final latest = _latestWithDistance(episode);
  if (latest == null) return null;
  final accuracy = latest.accuracyMeters ?? radiusMeters;
  if (accuracy > radiusMeters * 1.5) return null;
  if (latest.isMocked) return false;
  return latest.distanceMeters! >= radiusMeters * config.departureHysteresisFactor;
}

/// True if the episode has at least two observations far enough apart in
/// time (i.e. from independent OS wake-ups, not one burst) agreeing on the
/// same directional signal — persistence of state over time is itself
/// evidence.
bool _hasTemporalPersistence(List<DetectionObservation> episode) {
  if (episode.length < 2) return false;
  final span = episode.last.timestamp.difference(episode.first.timestamp);
  return span >= const Duration(seconds: 45);
}

ConfidenceResult computeArrivalConfidence({
  required List<DetectionObservation> episode,
  required double radiusMeters,
  required DateTime firstEnterTimestamp,
  required bool nativeDwellSeen,
  required DetectionConfig config,
  bool? historicalSupportsNow,
}) {
  if (episode.isEmpty) {
    return const ConfidenceResult(
      confidence: 0,
      evidence: DetectionEvidence(),
    );
  }

  final softDwellElapsed =
      episode.last.timestamp.difference(firstEnterTimestamp) >=
      config.softDwellDuration;
  final geofenceSupported = nativeDwellSeen || softDwellElapsed;

  final locationSupported = _arrivalLocationEvidence(episode, radiusMeters, config);

  final latestActivity = _latestWithActivity(episode);
  bool? activitySupported;
  if (latestActivity != null) {
    final polarity = activityArrivalPolarity(latestActivity.activity);
    activitySupported = polarity > 0 ? true : (polarity < 0 ? false : null);
  }

  final latestNetwork = _latestWithNetwork(episode);
  final networkSupported = latestNetwork?.workplaceNetworkDetected;

  final temporalSupported = _hasTemporalPersistence(episode);

  final confidence = _aggregate([
    _WeightedEvidence(config.geofenceWeight, geofenceSupported),
    _WeightedEvidence(config.locationWeight, locationSupported),
    _WeightedEvidence(config.activityWeight, activitySupported),
    _WeightedEvidence(config.networkWeight, networkSupported),
    _WeightedEvidence(config.temporalWeight, temporalSupported),
    _WeightedEvidence(config.historicalWeight, historicalSupportsNow),
  ]);

  return ConfidenceResult(
    confidence: confidence,
    evidence: DetectionEvidence(
      geofence: geofenceSupported,
      location: locationSupported,
      activity: activitySupported,
      network: networkSupported,
      temporal: temporalSupported,
      historical: historicalSupportsNow,
    ),
  );
}

ConfidenceResult computeDepartureConfidence({
  required List<DetectionObservation> episode,
  required double radiusMeters,
  required DateTime firstExitTimestamp,
  required DetectionConfig config,
  bool? historicalSupportsNow,
}) {
  if (episode.isEmpty) {
    return const ConfidenceResult(
      confidence: 0,
      evidence: DetectionEvidence(),
    );
  }

  // "Geofence" evidence for departure = sustained absence: the confirming
  // sample is at least softDwellDuration/2 after the first exit signal, i.e.
  // it wasn't an instantaneous jitter blip.
  final sustainedAbsence =
      episode.last.timestamp.difference(firstExitTimestamp) >=
      Duration(
        milliseconds: config.softDwellDuration.inMilliseconds ~/ 2,
      );

  final locationSupported = _departureLocationEvidence(episode, radiusMeters, config);

  final latestActivity = _latestWithActivity(episode);
  bool? activitySupported;
  if (latestActivity != null) {
    final polarity = activityDeparturePolarity(latestActivity.activity);
    activitySupported = polarity > 0 ? true : (polarity < 0 ? false : null);
  }

  final latestNetwork = _latestWithNetwork(episode);
  // Losing the workplace network supports departure; still seeing it opposes.
  final networkSupported = latestNetwork?.workplaceNetworkDetected == null
      ? null
      : !latestNetwork!.workplaceNetworkDetected!;

  final temporalSupported = _hasTemporalPersistence(episode) && sustainedAbsence;

  final confidence = _aggregate([
    _WeightedEvidence(config.geofenceWeight, sustainedAbsence),
    _WeightedEvidence(config.locationWeight, locationSupported),
    _WeightedEvidence(config.activityWeight, activitySupported),
    _WeightedEvidence(config.networkWeight, networkSupported),
    _WeightedEvidence(config.temporalWeight, temporalSupported),
    _WeightedEvidence(config.historicalWeight, historicalSupportsNow),
  ]);

  return ConfidenceResult(
    confidence: confidence,
    evidence: DetectionEvidence(
      geofence: sustainedAbsence,
      location: locationSupported,
      activity: activitySupported,
      network: networkSupported,
      temporal: temporalSupported,
      historical: historicalSupportsNow,
    ),
  );
}
