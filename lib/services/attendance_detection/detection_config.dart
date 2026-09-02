/// Tunable thresholds/durations/weights for the attendance detection engine.
///
/// Every magic number the engine uses lives here, documented, instead of
/// scattered through the state machine/confidence engine. See
/// docs/AUTO_ATTENDANCE_DESIGN.md section 6 for the rationale behind each
/// default.
class DetectionConfig {
  /// Arrival confidence at/above this creates an automatic CHECK_IN.
  final double arrivalHighThreshold;

  /// Arrival confidence below this discards the episode's "arrival attempt"
  /// back toward NEAR_WORKPLACE instead of lingering in POSSIBLE_ARRIVAL.
  final double arrivalContinueThreshold;

  /// Departure confidence at/above this creates an automatic CHECK_OUT.
  final double departureHighThreshold;

  /// Departure confidence below this discards the "departure attempt" back
  /// toward AT_WORKPLACE.
  final double departureContinueThreshold;

  /// Elapsed time inside the geofence radius with no intervening EXIT that
  /// counts as dwell evidence even without a native DWELL event (iOS has no
  /// native dwell trigger — see design doc section 2/10).
  final Duration softDwellDuration;

  /// If EXIT arrives within this of the first ENTER with no dwell evidence
  /// at all, the whole episode is discarded (the "drove past" case).
  final Duration passByGraceDuration;

  /// Re-entry within this window while still POSSIBLE_DEPARTURE cancels the
  /// departure and returns to AT_WORKPLACE (the "went to another floor"
  /// case).
  final Duration departureCancelWindow;

  /// Distance must exceed `radiusMeters * departureHysteresisFactor` to
  /// count as strong departure location evidence, damping boundary jitter.
  final double departureHysteresisFactor;

  /// Distance must be at/under this fraction of the radius to count as
  /// strong arrival location evidence (tighter than the raw geofence edge).
  final double arrivalProximityFactor;

  /// Bounds on retained per-episode observation history.
  final int maxEpisodeObservations;
  final Duration maxEpisodeAge;

  // Evidence weights. Must sum to 1.0; renormalized at evaluation time over
  // whichever evidence components are actually available for the episode
  // (e.g. network evidence is commonly unavailable, especially on iOS).
  final double geofenceWeight;
  final double locationWeight;
  final double activityWeight;
  final double networkWeight;
  final double temporalWeight;
  final double historicalWeight;

  const DetectionConfig({
    required this.arrivalHighThreshold,
    required this.arrivalContinueThreshold,
    required this.departureHighThreshold,
    required this.departureContinueThreshold,
    required this.softDwellDuration,
    required this.passByGraceDuration,
    required this.departureCancelWindow,
    required this.departureHysteresisFactor,
    required this.arrivalProximityFactor,
    required this.maxEpisodeObservations,
    required this.maxEpisodeAge,
    required this.geofenceWeight,
    required this.locationWeight,
    required this.activityWeight,
    required this.networkWeight,
    required this.temporalWeight,
    required this.historicalWeight,
  });

  static const DetectionConfig defaultConfig = DetectionConfig(
    arrivalHighThreshold: 0.72,
    arrivalContinueThreshold: 0.30,
    departureHighThreshold: 0.68,
    departureContinueThreshold: 0.28,
    softDwellDuration: Duration(minutes: 3),
    passByGraceDuration: Duration(minutes: 2),
    departureCancelWindow: Duration(minutes: 10),
    departureHysteresisFactor: 1.15,
    arrivalProximityFactor: 0.85,
    maxEpisodeObservations: 40,
    maxEpisodeAge: Duration(hours: 20),
    geofenceWeight: 0.30,
    locationWeight: 0.25,
    activityWeight: 0.25,
    networkWeight: 0.10,
    temporalWeight: 0.05,
    historicalWeight: 0.05,
  );
}
