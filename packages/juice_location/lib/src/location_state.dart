import 'package:juice/juice.dart';

import 'location_source.dart';

/// Rebuild groups emitted by [LocationBloc].
abstract final class LocationGroups {
  /// The current position changed.
  static const position = 'location:position';

  /// Tracking started/stopped.
  static const tracking = 'location:tracking';

  /// The (externally-set) permission status changed.
  static const permission = 'location:permission';

  /// An error occurred reading location.
  static const error = 'location:error';

  static const all = {position, tracking, permission, error};
}

/// Immutable location state.
class LocationState extends BlocState {
  /// The most recent position, or null before the first fix.
  final GeoPosition? current;

  /// Whether continuous tracking is active.
  final bool tracking;

  /// Whether the app may read location. Set via
  /// [LocationBloc.setPermissionStatus] — typically wired from
  /// `juice_permissions` with a `PermissionBinding`. Informational.
  final bool permissionGranted;

  /// Last error message, if any.
  final String? lastError;

  const LocationState({
    this.current,
    this.tracking = false,
    this.permissionGranted = false,
    this.lastError,
  });

  static const initial = LocationState();

  LocationState copyWith({
    GeoPosition? current,
    bool? tracking,
    bool? permissionGranted,
    String? lastError,
    bool clearError = false,
  }) {
    return LocationState(
      current: current ?? this.current,
      tracking: tracking ?? this.tracking,
      permissionGranted: permissionGranted ?? this.permissionGranted,
      lastError: clearError ? null : (lastError ?? this.lastError),
    );
  }

  @override
  String toString() =>
      'LocationState($current, tracking: $tracking, granted: $permissionGranted)';
}
