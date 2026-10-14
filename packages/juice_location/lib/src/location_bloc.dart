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
import 'use_cases/tracking_ended_use_case.dart';

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
  LocationConfig? _config;

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
                  typeOfEvent: TrackingEndedEvent,
                  useCaseGenerator: () => TrackingEndedUseCase(),
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
  LocationSource get source => config.source;

  /// The config [InitializeLocationEvent] applied. Throws before that.
  LocationConfig get config =>
      _config ??
      (throw StateError(
          'LocationBloc is not initialized: send InitializeLocationEvent '
          '(or use LocationBloc.withConfig) first'));

  /// Store the config during initialization. One per bloc: a second
  /// `InitializeLocationEvent` after the first completed is refused here (the
  /// first provider stays owned and live), loudly, through the use case's
  /// error path.
  void configure(LocationConfig config) {
    if (_config != null) {
      throw StateError(
          'LocationBloc is already initialized; it owns one config for its life');
    }
    _config = config;
  }

  /// Subscribe to the position stream (called by [StartTrackingEvent]).
  /// The bloc owns the binding: a second start replaces the first, and
  /// close cancels it before the use cases close. A stream that errors or
  /// ends is no longer tracking: the state says so, with the error.
  void startTracking() {
    bindStream<GeoPosition>(
      source.positions(),
      (position) => send(LocationChangedEvent(position)),
      key: _trackingKey,
      onError: (error, stackTrace) =>
          send(TrackingEndedEvent(error: error.toString())),
      onDone: () => send(TrackingEndedEvent()),
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

  // Memoized like the core's close(): a second caller awaits the first
  // teardown, so the provider is disposed once. `super.close()` is invoked
  // here (the core requires it) and awaited inside.
  @override
  Future<void> close() => _closeOnce ??= _close(super.close());
  Future<void>? _closeOnce;

  Future<void> _close(Future<void> closing) async {
    // The bloc closes first: its tracking binding is cancelled before the
    // source it listens to is disposed. An uninitialized bloc has no source.
    await closing;
    final config = _config;
    if (config == null) return;
    try {
      await config.source.dispose();
    } catch (error, stackTrace) {
      JuiceLoggerConfig.logger.logError(
          'LocationSource dispose failed', error, stackTrace,
          context: {'type': 'bloc_error', 'bloc': 'LocationBloc'});
    }
  }
}
