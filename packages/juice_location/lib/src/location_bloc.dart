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
  StreamSubscription<GeoPosition>? _trackingSubscription;

  LocationBloc()
      : super(
          LocationState.initial,
          [
            () => UseCaseBuilder(
                  typeOfEvent: InitializeLocationEvent,
                  useCaseGenerator: () => InitializeLocationUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: GetCurrentLocationEvent,
                  useCaseGenerator: () => GetCurrentLocationUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: StartTrackingEvent,
                  useCaseGenerator: () => StartTrackingUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: StopTrackingEvent,
                  useCaseGenerator: () => StopTrackingUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: LocationChangedEvent,
                  useCaseGenerator: () => LocationChangedUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: SetPermissionStatusEvent,
                  useCaseGenerator: () => SetPermissionStatusUseCase(),
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
  void startTracking() {
    _trackingSubscription = source.positions().listen((position) {
      if (!isClosed) send(LocationChangedEvent(position));
    });
  }

  /// Cancel the position subscription (called by [StopTrackingEvent]).
  void stopTracking() {
    _trackingSubscription?.cancel();
    _trackingSubscription = null;
  }

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
    await _trackingSubscription?.cancel();
    try {
      await _config.source.dispose();
    } catch (_) {
      // Source may never have been configured; ignore.
    }
    await super.close();
  }
}
