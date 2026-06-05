/// Device location as a Juice bloc.
///
/// `LocationBloc` owns the current position and continuous tracking, through a
/// swappable [LocationSource] seam (default `GeolocatorLocationSource`).
/// Permission status is set externally via [LocationBloc.setPermissionStatus] —
/// wire it from `juice_permissions` with a `PermissionBinding`.
///
/// ```dart
/// final location = LocationBloc.withConfig(LocationConfig());
/// location.getCurrent();
///
/// PermissionBinding(permissions, JuicePermission.locationWhenInUse,
///   onStatus: (s) => location.setPermissionStatus(s == PermissionStatus.granted),
/// )..start();
/// ```
library juice_location;

export 'src/location_bloc.dart';
export 'src/location_config.dart';
export 'src/location_events.dart';
export 'src/location_source.dart';
export 'src/location_state.dart';
export 'src/providers/geolocator_location_source.dart';
