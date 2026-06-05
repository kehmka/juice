/// A vendor-agnostic position fix.
class GeoPosition {
  final double latitude;
  final double longitude;

  /// Estimated accuracy in metres.
  final double accuracy;

  /// Altitude in metres (0 if unavailable).
  final double altitude;

  /// Speed in m/s (0 if unavailable).
  final double speed;

  /// Heading in degrees (0 if unavailable).
  final double heading;

  /// When the fix was taken.
  final DateTime timestamp;

  const GeoPosition({
    required this.latitude,
    required this.longitude,
    this.accuracy = 0,
    this.altitude = 0,
    this.speed = 0,
    this.heading = 0,
    required this.timestamp,
  });

  @override
  String toString() =>
      'GeoPosition($latitude, $longitude ±${accuracy}m)';
}

/// Vendor seam for device location.
///
/// `LocationBloc` depends on this interface, not on a plugin — testable with a
/// fake. The default implementation is `GeolocatorLocationSource`.
abstract class LocationSource {
  /// One-shot current position.
  Future<GeoPosition> current();

  /// Continuous position updates (subscribed while tracking).
  Stream<GeoPosition> positions();

  /// Release resources.
  Future<void> dispose();
}
