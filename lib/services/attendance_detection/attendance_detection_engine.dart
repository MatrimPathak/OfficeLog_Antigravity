import 'detection_config.dart';
import 'detection_diagnostics.dart';
import 'detection_models.dart';
import 'detection_persistence.dart';
import 'detection_state_machine.dart';
import 'signal_sources/activity_signal_source.dart';
import 'signal_sources/location_signal_source.dart';
import 'signal_sources/network_signal_source.dart';

/// Facade tying the pure state machine/confidence/timestamp logic to
/// platform signal sources and persistence. This is the only class
/// `AutoCheckInService` talks to — see docs/AUTO_ATTENDANCE_DESIGN.md.
///
/// Responsible for:
///  - turning one OS-delivered event (geofence transition or an explicit
///    app-foreground check) into a single bounded "burst" of signal reads,
///  - loading/saving the per-user persisted [DetectionEngineState],
///  - writing structured diagnostics for every observation/transition/
///    decision.
///
/// Deliberately knows nothing about Firestore, attendance rules, or the
/// working-day/capture-times toggles — those stay in `AutoCheckInService`,
/// which decides what to *do* with an [AttendanceDecision].
class AttendanceDetectionEngine {
  final DetectionPersistence _persistence;
  final DetectionStateMachine _stateMachine;
  final LocationSignalSource _locationSource;
  final ActivitySignalSource _activitySource;
  final NetworkSignalSource _networkSource;

  AttendanceDetectionEngine({
    required ActivitySignalSource activitySource,
    required NetworkSignalSource networkSource,
    DetectionPersistence? persistence,
    DetectionConfig config = DetectionConfig.defaultConfig,
    LocationSignalSource? locationSource,
  }) : _persistence = persistence ?? DetectionPersistence(),
       _stateMachine = DetectionStateMachine(config: config),
       _locationSource = locationSource ?? LocationSignalSource(),
       _activitySource = activitySource,
       _networkSource = networkSource;

  /// Feeds a native geofence [transition] into the engine. Returns a
  /// decision only when confidence just crossed the automatic-action
  /// threshold this call — most calls return null (still collecting
  /// evidence, or nothing changed).
  Future<AttendanceDecision?> processGeofenceEvent({
    required String userId,
    required GeofenceTransition transition,
    required double officeLat,
    required double officeLng,
    required double radiusMeters,
    required bool allowMockLocation,
    bool? historicalSupportsArrivalNow,
    bool? historicalSupportsDepartureNow,
  }) {
    return _handle(
      userId: userId,
      transition: transition,
      source: 'geofence',
      officeLat: officeLat,
      officeLng: officeLng,
      radiusMeters: radiusMeters,
      allowMockLocation: allowMockLocation,
      historicalSupportsArrivalNow: historicalSupportsArrivalNow,
      historicalSupportsDepartureNow: historicalSupportsDepartureNow,
    );
  }

  /// Feeds an opportunistic sample from the app being brought to the
  /// foreground (e.g. app resume) into the engine — the same evidence
  /// pipeline as a geofence event, just without a native transition
  /// attached. Lets the engine make progress even between OS wake-ups, and
  /// covers "user opens the app after an automatic event should have
  /// occurred."
  Future<AttendanceDecision?> processForegroundCheck({
    required String userId,
    required double officeLat,
    required double officeLng,
    required double radiusMeters,
    required bool allowMockLocation,
    bool? historicalSupportsArrivalNow,
    bool? historicalSupportsDepartureNow,
  }) {
    return _handle(
      userId: userId,
      transition: null,
      source: 'foreground_check',
      officeLat: officeLat,
      officeLng: officeLng,
      radiusMeters: radiusMeters,
      allowMockLocation: allowMockLocation,
      historicalSupportsArrivalNow: historicalSupportsArrivalNow,
      historicalSupportsDepartureNow: historicalSupportsDepartureNow,
    );
  }

  /// Discards any in-progress episode/state for [userId] — used when the
  /// user disables auto check-in or changes the workplace location, so a
  /// stale episode from the old configuration can't produce a decision
  /// under the new one.
  Future<void> reset(String userId) => _persistence.clear(userId);

  Future<AttendanceDecision?> _handle({
    required String userId,
    required GeofenceTransition? transition,
    required String source,
    required double officeLat,
    required double officeLng,
    required double radiusMeters,
    required bool allowMockLocation,
    bool? historicalSupportsArrivalNow,
    bool? historicalSupportsDepartureNow,
  }) async {
    final location = await _locationSource.fetchSample(
      officeLat: officeLat,
      officeLng: officeLng,
    );

    if (location.isMocked && !allowMockLocation) {
      DetectionDiagnostics.logTransition(
        'blocked: mock location detected and not allowed',
      );
      return null;
    }

    final activity = await _activitySource.currentActivity();
    final network = await _networkSource.isConnectedToWorkplaceNetwork();

    bool? workplaceRegionActive;
    if (transition == GeofenceTransition.enter ||
        transition == GeofenceTransition.dwell) {
      workplaceRegionActive = true;
    } else if (transition == GeofenceTransition.exit) {
      workplaceRegionActive = false;
    } else if (location.distanceMeters != null) {
      workplaceRegionActive = location.distanceMeters! <= radiusMeters;
    }

    final observation = DetectionObservation(
      timestamp: DateTime.now(),
      activity: activity,
      distanceMeters: location.distanceMeters,
      accuracyMeters: location.accuracyMeters,
      workplaceNetworkDetected: network,
      workplaceRegionActive: workplaceRegionActive,
      transition: transition,
      isMocked: location.isMocked,
      source: source,
    );
    DetectionDiagnostics.logObservation(observation);

    final currentState = await _persistence.load(userId);
    final result = _stateMachine.process(
      current: currentState,
      observation: observation,
      radiusMeters: radiusMeters,
      historicalSupportsArrivalNow: historicalSupportsArrivalNow,
      historicalSupportsDepartureNow: historicalSupportsDepartureNow,
    );
    await _persistence.save(userId, result.nextState);
    DetectionDiagnostics.logTransition(
      'state=${result.nextState.state.name} ${result.diagnosticSummary}',
    );
    if (result.decision != null) {
      DetectionDiagnostics.logDecision(result.decision!);
    }
    return result.decision;
  }
}
