import 'package:juice/juice.dart';

import 'flags_config.dart';

/// Base class for flags events.
abstract class FlagsEvent extends EventBase {
  @override
  String toString() => runtimeType.toString();
}

/// Apply config: seed defaults, subscribe to live updates, optional first fetch.
class InitializeFlagsEvent extends FlagsEvent {
  final FlagsConfig config;
  InitializeFlagsEvent({required this.config});
}

/// Pull the latest values from the source.
class RefreshFlagsEvent extends FlagsEvent {}

/// Internal: new values arrived (from a fetch or the live stream).
class FlagsUpdatedEvent extends FlagsEvent {
  final Map<String, Object?> values;
  FlagsUpdatedEvent(this.values);
}

/// Internal: a fetch failed.
class FlagsFetchFailedEvent extends FlagsEvent {
  final Object error;
  FlagsFetchFailedEvent(this.error);
}

/// Set a local override (e.g. a dev toggle). Wins over fetched values until
/// cleared.
class SetFlagOverrideEvent extends FlagsEvent {
  final String key;
  final Object? value;
  SetFlagOverrideEvent(this.key, this.value);
}

/// Clear a local override, reverting to the fetched/default value.
class ClearFlagOverrideEvent extends FlagsEvent {
  final String key;
  ClearFlagOverrideEvent(this.key);
}
