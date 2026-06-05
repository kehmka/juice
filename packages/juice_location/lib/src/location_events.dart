import 'package:juice/juice.dart';

import 'location_config.dart';
import 'location_source.dart';

/// Base class for location events.
abstract class LocationEvent extends EventBase {
  @override
  String toString() => runtimeType.toString();
}

/// Configure the source.
class InitializeLocationEvent extends LocationEvent {
  final LocationConfig config;
  InitializeLocationEvent({required this.config});
}

/// Read the current position once.
class GetCurrentLocationEvent extends LocationEvent {}

/// Start continuous tracking.
class StartTrackingEvent extends LocationEvent {}

/// Stop continuous tracking.
class StopTrackingEvent extends LocationEvent {}

/// Internal: a new position arrived (one-shot or stream).
class LocationChangedEvent extends LocationEvent {
  final GeoPosition position;
  LocationChangedEvent(this.position);
}

/// Set whether the app may read location (wire from `juice_permissions`).
class SetPermissionStatusEvent extends LocationEvent {
  final bool granted;
  SetPermissionStatusEvent(this.granted);
}
