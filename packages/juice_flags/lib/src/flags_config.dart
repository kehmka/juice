import 'flags_source.dart';

/// Configures a `FlagsBloc`.
class FlagsConfig {
  /// Where values come from. Defaults to an empty [StaticFlagsSource]; swap for
  /// a remote adapter (e.g. Firebase Remote Config) in a real app.
  final FlagsSource source;

  /// Baseline values, used before the first fetch and as the floor a read falls
  /// back to. Flags must always resolve — these guarantee a safe value.
  final Map<String, Object?> defaults;

  /// Fetch on initialization. Set false to fetch manually via `refresh()`.
  final bool fetchOnInit;

  FlagsConfig({
    FlagsSource? source,
    this.defaults = const {},
    this.fetchOnInit = true,
  }) : source = source ?? StaticFlagsSource();
}
