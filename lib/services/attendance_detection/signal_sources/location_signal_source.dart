import 'package:geolocator/geolocator.dart';

/// One bounded, on-demand location sample — never a continuous stream. This
/// is the only "burst" of GPS activity the detection engine performs, run
/// solely inside an OS-delivered geofence/foreground-check handler. See
/// docs/AUTO_ATTENDANCE_DESIGN.md section 8 (battery strategy).
class LocationSample {
  final double? distanceMeters;
  final double? accuracyMeters;
  final bool isMocked;

  const LocationSample({
    this.distanceMeters,
    this.accuracyMeters,
    this.isMocked = false,
  });

  static const unavailable = LocationSample();
}

/// Wraps `geolocator` for the detection engine's on-demand location bursts.
/// Accuracy/timeout preserved from the pre-existing `AutoCheckInService`
/// implementation this replaces.
class LocationSignalSource {
  Future<LocationSample> fetchSample({
    required double officeLat,
    required double officeLng,
  }) async {
    Position? position;
    try {
      position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 3),
        ),
      );
    } catch (_) {
      try {
        position = await Geolocator.getLastKnownPosition();
      } catch (_) {
        position = null;
      }
    }

    if (position == null) return LocationSample.unavailable;

    final distance = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      officeLat,
      officeLng,
    );

    return LocationSample(
      distanceMeters: distance,
      accuracyMeters: position.accuracy,
      isMocked: position.isMocked,
    );
  }
}
