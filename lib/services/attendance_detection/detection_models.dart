/// Cross-platform common event model for automatic attendance detection.
///
/// Platform adapters (geofence, location, activity) only ever produce
/// [DetectionObservation]s. The shared engine in this directory never sees a
/// raw `Position`, native geofence callback, or activity-recognition event
/// directly — see docs/AUTO_ATTENDANCE_DESIGN.md section 3.
library;

/// Normalized activity classification, shared across Android's
/// ActivityRecognitionClient and iOS's CMMotionActivityManager vocabularies.
enum DetectionActivity { stationary, walking, running, cycling, vehicle, unknown }

/// Native geofence transition, when an observation was produced by one.
enum GeofenceTransition { enter, exit, dwell }

/// Explicit attendance detection state machine states.
enum AttendanceDetectionState {
  unknown,
  nearWorkplace,
  possibleArrival,
  atWorkplace,
  possibleDeparture,
  awayFromWorkplace,
}

/// The kind of automatic attendance decision the engine can emit.
enum AttendanceDecisionType { checkIn, checkOut }

/// A single normalized observation feeding the detection engine.
///
/// Deliberately does NOT carry raw latitude/longitude — only the derived
/// [distanceMeters] a platform adapter already had to compute. See
/// docs/AUTO_ATTENDANCE_DESIGN.md section 8 (privacy).
class DetectionObservation {
  final DateTime timestamp;
  final DetectionActivity activity;
  final double? distanceMeters;
  final double? accuracyMeters;
  final bool? workplaceNetworkDetected;
  final bool? workplaceRegionActive;
  final GeofenceTransition? transition;
  final bool isMocked;
  final String source;

  const DetectionObservation({
    required this.timestamp,
    required this.activity,
    this.distanceMeters,
    this.accuracyMeters,
    this.workplaceNetworkDetected,
    this.workplaceRegionActive,
    this.transition,
    this.isMocked = false,
    required this.source,
  });

  Map<String, dynamic> toMap() => {
    'timestamp': timestamp.toIso8601String(),
    'activity': activity.name,
    'distanceMeters': distanceMeters,
    'accuracyMeters': accuracyMeters,
    'workplaceNetworkDetected': workplaceNetworkDetected,
    'workplaceRegionActive': workplaceRegionActive,
    'transition': transition?.name,
    'isMocked': isMocked,
    'source': source,
  };

  factory DetectionObservation.fromMap(Map<dynamic, dynamic> map) {
    return DetectionObservation(
      timestamp: DateTime.parse(map['timestamp'] as String),
      activity: DetectionActivity.values.firstWhere(
        (e) => e.name == map['activity'],
        orElse: () => DetectionActivity.unknown,
      ),
      distanceMeters: (map['distanceMeters'] as num?)?.toDouble(),
      accuracyMeters: (map['accuracyMeters'] as num?)?.toDouble(),
      workplaceNetworkDetected: map['workplaceNetworkDetected'] as bool?,
      workplaceRegionActive: map['workplaceRegionActive'] as bool?,
      transition: map['transition'] != null
          ? GeofenceTransition.values.firstWhere(
              (e) => e.name == map['transition'],
              orElse: () => GeofenceTransition.enter,
            )
          : null,
      isMocked: map['isMocked'] as bool? ?? false,
      source: map['source'] as String? ?? 'unknown',
    );
  }
}

/// Structured evidence breakdown backing a confidence score, used both for
/// the automatic decision and for diagnostics ("why was I checked in/out").
class DetectionEvidence {
  final bool? geofence; // dwell (native or soft) evidence present
  final bool? location; // distance/accuracy support the verdict
  final bool? activity; // activity classification supports the verdict
  final bool? network; // optional workplace network signal (may be null: unavailable)
  final bool? temporal; // state persisted across multiple independent samples
  final bool? historical; // near the user's typical arrival/departure time

  const DetectionEvidence({
    this.geofence,
    this.location,
    this.activity,
    this.network,
    this.temporal,
    this.historical,
  });

  Map<String, dynamic> toMap() => {
    'geofence': geofence,
    'location': location,
    'activity': activity,
    'network': network,
    'temporal': temporal,
    'historical': historical,
  };
}

/// A fully-formed automatic attendance decision the engine emits once
/// confidence crosses the high threshold. Carries enough metadata to debug
/// the decision later, per docs/AUTO_ATTENDANCE_DESIGN.md section 9.
class AttendanceDecision {
  final AttendanceDecisionType type;
  final DateTime estimatedTimestamp;
  final double confidence;
  final DetectionEvidence evidence;
  final String timestampRationale;
  final double? distanceMetersAtConfirmation;
  final double? accuracyMetersAtConfirmation;
  final DetectionActivity activityAtConfirmation;

  const AttendanceDecision({
    required this.type,
    required this.estimatedTimestamp,
    required this.confidence,
    required this.evidence,
    required this.timestampRationale,
    this.distanceMetersAtConfirmation,
    this.accuracyMetersAtConfirmation,
    required this.activityAtConfirmation,
  });

  /// Debug metadata attached to the AttendanceSession that this decision
  /// produces (AttendanceSession.autoMetadata). Intentionally excludes raw
  /// coordinates.
  Map<String, dynamic> toAttendanceMetadata() => {
    'method': 'automatic',
    'type': type.name,
    'confidence': double.parse(confidence.toStringAsFixed(2)),
    'distanceFromWorkplaceMeters': distanceMetersAtConfirmation,
    'locationAccuracyMeters': accuracyMetersAtConfirmation,
    'activity': activityAtConfirmation.name,
    'evidence': evidence.toMap(),
    'timestampRationale': timestampRationale,
  };
}
