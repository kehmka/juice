import 'package:juice/juice.dart';

import 'location_config.dart';
import 'location_events.dart';
import 'location_source.dart';
import 'location_state.dart';
import 'use_cases/get_current_location_use_case.dart';
import 'use_cases/initialize_location_use_case.dart';
import 'use_cases/location_changed_use_case.dart';
import 'use_cases/set_permission_status_use_case.dart';
import 'use_cases/start_tracking_use_case.dart';
import 'use_cases/stop_tracking_use_case.dart';

/// Bloc that owns the device's location — one-shot reads and continuous tracking.
///
/// Reads through a [LocationSource] seam (default `GeolocatorLocationSource`),
/// so it is testable without a device. Permission status is set externally via
/// [setPermissionStatus] — typically wired from `juice_permissions` with a
/// `PermissionBinding`.
///
/// ```dart
/// final location = LocationBloc.withConfig(LocationConfig());
/// location.getCurrent();      // one-shot
/// location.startTracking();   // continuous
/// ```
class LocationBloc extends JuiceBloc<LocationState> {
  late LocationConfig _config;

  LocationBloc()
      : super(
          LocationState.initial,
          [
            () => UseCaseBuilder(
                  typeOfEvent: InitializeLocationEvent,
                  useCaseGenerator: () => InitializeLocationUseCase(),
                  concurrency: EventConcurrency.droppable,
                ),
            () => UseCaseBuilder(
                  typeOfEvent: GetCurrentLocationEvent,
                  useCaseGenerator: () => GetCurrentLocationUseCase(),
                  concurrency: EventConcurrency.droppable,
                ),
            () => UseCaseBuilder(
                  typeOfEvent: StartTrackingEvent,
                  useCaseGenerator: () => StartTrackingUseCase(),
                  concurrency: EventConcurrency.sequential,
                ),
            () => UseCaseBuilder(
                  typeOfEvent: StopTrackingEvent,
                  useCaseGenerator: () => StopTrackingUseCase(),
                  concurrency: EventConcurrency.sequential,
                ),
            () => UseCaseBuilder(
                  typeOfEvent: LocationChangedEvent,
                  useCaseGenerator: () => LocationChangedUseCase(),
                  concurrency: EventConcurrency.sequential,
                ),
            () => UseCaseBuilder(
                  typeOfEvent: SetPermissionStatusEvent,
                  useCaseGenerator: () => SetPermissionStatusUseCase(),
                  concurrency: EventConcurrency.sequential,
                ),
          ],
        );

  /// Create and initialize in one step.
  factory LocationBloc.withConfig(LocationConfig config) {
    final bloc = LocationBloc();
    bloc.send(InitializeLocationEvent(config: config));
    return bloc;
  }

  /// The active source. Valid after initialization.
  LocationSource get source => _config.source;

  /// Store config during initialization.
  void configure(LocationConfig config) => _config = config;

  /// Subscribe to the position stream (called by [StartTrackingEvent]).
  /// The bloc owns the binding: a second start replaces the first, and
  /// close cancels it before the use cases close.
  void startTracking() {
    bindStream<GeoPosition>(
      source.positions(),
      (position) => send(LocationChangedEvent(position)),
      key: _trackingKey,
    );
  }

  /// Cancel the position subscription (called by [StopTrackingEvent]).
  void stopTracking() => unbind(_trackingKey);

  static const _trackingKey = 'tracking';

  // === Convenience ===

  /// Read the current position once.
  void getCurrent() => send(GetCurrentLocationEvent());

  /// Start continuous tracking.
  void startTrackingUpdates() => send(StartTrackingEvent());

  /// Stop continuous tracking.
  void stopTrackingUpdates() => send(StopTrackingEvent());

  /// Set whether reading is allowed (wire from `juice_permissions`).
  void setPermissionStatus(bool granted) =>
      send(SetPermissionStatusEvent(granted));

  @override
  Future<void> close() async {
    try {
      await _config.source.dispose();
    } catch (_) {
      // Source may never have been configured; ignore.
    }
    await super.close();
  }
}
