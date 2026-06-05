import 'location_source.dart';
import 'providers/geolocator_location_source.dart';

/// Configuration for [LocationBloc].
class LocationConfig {
  /// The location backend. Defaults to [GeolocatorLocationSource].
  ///
  /// Pass a fake here in tests to drive positions without a device.
  final LocationSource source;

  LocationConfig({LocationSource? source})
      : source = source ?? GeolocatorLocationSource();
}
