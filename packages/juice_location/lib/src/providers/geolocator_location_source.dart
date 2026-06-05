import 'package:geolocator/geolocator.dart';

import '../location_source.dart';

/// Default [LocationSource] backed by `geolocator`.
///
/// Deliberately logic-light: it maps `geolocator` positions to [GeoPosition].
/// All behavior lives in `LocationBloc`, tested with a fake source — this
/// adapter is verified by inspection and a one-time on-device run.
class GeolocatorLocationSource implements LocationSource {
  /// Desired accuracy for fixes.
  final LocationAccuracy accuracy;

  GeolocatorLocationSource({this.accuracy = LocationAccuracy.high});

  LocationSettings get _settings => LocationSettings(accuracy: accuracy);

  @override
  Future<GeoPosition> current() async =>
      _map(await Geolocator.getCurrentPosition(locationSettings: _settings));

  @override
  Stream<GeoPosition> positions() =>
      Geolocator.getPositionStream(locationSettings: _settings).map(_map);

  @override
  Future<void> dispose() async {}

  GeoPosition _map(Position p) => GeoPosition(
        latitude: p.latitude,
        longitude: p.longitude,
        accuracy: p.accuracy,
        altitude: p.altitude,
        speed: p.speed,
        heading: p.heading,
        timestamp: p.timestamp,
      );
}
