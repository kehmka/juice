import 'package:juice/juice.dart';

import 'flags_config.dart';
import 'flags_events.dart';
import 'flags_source.dart';
import 'flags_state.dart';
import 'use_cases/clear_flag_override_use_case.dart';
import 'use_cases/flags_fetch_failed_use_case.dart';
import 'use_cases/flags_updated_use_case.dart';
import 'use_cases/initialize_flags_use_case.dart';
import 'use_cases/refresh_flags_use_case.dart';
import 'use_cases/set_flag_override_use_case.dart';

/// A feature-flags / remote-config bloc, vendor-free behind a [FlagsSource]
/// seam, with **per-flag selective rebuilds**.
///
/// Values resolve in layers: `defaults < fetched < overrides`. Reads always
/// return *something* via the typed accessors, so a flag never renders
/// "unknown". A fetch failure is surfaced loudly in `state.error` while reads
/// keep falling back to last-known/defaults.
///
/// ```dart
/// final flags = FlagsBloc.withConfig(FlagsConfig(
///   source: FirebaseRemoteConfigFlagsSource(FirebaseRemoteConfig.instance),
///   defaults: {'new_checkout': false, 'max_items': 20},
/// ));
/// if (flags.boolFlag('new_checkout')) showNewCheckout();
/// ```
class FlagsBloc extends JuiceBloc<FlagsState> {
  late FlagsConfig _config;
  StreamSubscription<Map<String, Object?>>? _changesSub;

  final Map<String, Object?> _defaults = {};
  final Map<String, Object?> _fetched = {};
  final Map<String, Object?> _overrides = {};

  FlagsBloc()
      : super(
          FlagsState.initial,
          [
            () => UseCaseBuilder(
                typeOfEvent: InitializeFlagsEvent,
                useCaseGenerator: () => InitializeFlagsUseCase()),
            () => UseCaseBuilder(
                typeOfEvent: RefreshFlagsEvent,
                useCaseGenerator: () => RefreshFlagsUseCase()),
            () => UseCaseBuilder(
                typeOfEvent: FlagsUpdatedEvent,
                useCaseGenerator: () => FlagsUpdatedUseCase()),
            () => UseCaseBuilder(
                typeOfEvent: FlagsFetchFailedEvent,
                useCaseGenerator: () => FlagsFetchFailedUseCase()),
            () => UseCaseBuilder(
                typeOfEvent: SetFlagOverrideEvent,
                useCaseGenerator: () => SetFlagOverrideUseCase()),
            () => UseCaseBuilder(
                typeOfEvent: ClearFlagOverrideEvent,
                useCaseGenerator: () => ClearFlagOverrideUseCase()),
          ],
        );

  /// Create and initialize in one step.
  factory FlagsBloc.withConfig(FlagsConfig config) {
    final bloc = FlagsBloc();
    bloc.send(InitializeFlagsEvent(config: config));
    return bloc;
  }

  // === Config / lifecycle (used by use cases) ===

  FlagsConfig get config => _config;

  /// The active source. Valid after initialization.
  FlagsSource get source => _config.source;

  /// Apply config: store it and seed the default layer.
  void configure(FlagsConfig config) {
    _config = config;
    _defaults
      ..clear()
      ..addAll(config.defaults);
  }

  /// Subscribe to live updates if the source provides them.
  void startListening() {
    final stream = _config.source.changes();
    if (stream == null) return;
    _changesSub = stream.listen(
      (values) {
        if (!isClosed) send(FlagsUpdatedEvent(values));
      },
      onError: (Object e) {
        if (!isClosed) send(FlagsFetchFailedEvent(e));
      },
    );
  }

  // === Value layers ===

  /// Resolve the layered value map: defaults < fetched < overrides.
  Map<String, Object?> resolve() => {..._defaults, ..._fetched, ..._overrides};

  /// Replace the fetched layer.
  void applyFetched(Map<String, Object?> values) {
    _fetched
      ..clear()
      ..addAll(values);
  }

  /// Set/clear a local override.
  void setOverride(String key, Object? value) => _overrides[key] = value;
  void clearOverride(String key) => _overrides.remove(key);

  /// Keys whose resolved value differs between [oldValues] and [newValues]
  /// (added, removed, or changed). Drives per-flag selective rebuilds.
  Set<String> changedKeys(
      Map<String, Object?> oldValues, Map<String, Object?> newValues) {
    final keys = {...oldValues.keys, ...newValues.keys};
    return keys
        .where((k) => oldValues[k] != newValues[k])
        .toSet();
  }

  // === Typed reads (always resolve to something) ===

  bool boolFlag(String key, {bool fallback = false}) {
    final v = state.values[key];
    return v is bool ? v : fallback;
  }

  String stringFlag(String key, {String fallback = ''}) {
    final v = state.values[key];
    return v is String ? v : fallback;
  }

  int intFlag(String key, {int fallback = 0}) {
    final v = state.values[key];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return fallback;
  }

  double doubleFlag(String key, {double fallback = 0}) {
    final v = state.values[key];
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return fallback;
  }

  /// Read a structured value (e.g. a decoded JSON map/list). Returns null if
  /// absent or not of type [T].
  T? json<T>(String key) {
    final v = state.values[key];
    return v is T ? v : null;
  }

  // === Convenience API ===

  void refresh() => send(RefreshFlagsEvent());
  void setFlagOverride(String key, Object? value) =>
      send(SetFlagOverrideEvent(key, value));
  void clearFlagOverride(String key) => send(ClearFlagOverrideEvent(key));

  @override
  Future<void> close() async {
    await _changesSub?.cancel();
    try {
      await _config.source.dispose();
    } catch (_) {
      // Source may never have been configured; ignore.
    }
    await super.close();
  }
}
