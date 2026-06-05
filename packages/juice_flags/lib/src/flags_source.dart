/// Vendor seam for resolving flag / remote-config values.
///
/// `FlagsBloc` depends on this interface, not on a vendor SDK — so Firebase
/// Remote Config, LaunchDarkly, a plain endpoint, or a local map are all just
/// implementations. Values are vendor-agnostic: `bool`, `num`, `String`, or a
/// JSON-decodable structure.
abstract class FlagsSource {
  /// Fetch the current values for all known flags.
  Future<Map<String, Object?>> fetch();

  /// Optional live updates (e.g. Firebase `onConfigUpdated`). Return null if
  /// the source is pull-only.
  Stream<Map<String, Object?>>? changes();

  /// Release resources.
  Future<void> dispose();
}

/// A pull-only, in-memory [FlagsSource] — the default.
///
/// Useful as a baseline, for tests, and for apps that ship flags locally. Swap
/// for a remote source (e.g. a Firebase Remote Config adapter) via
/// `FlagsConfig(source: ...)`.
class StaticFlagsSource implements FlagsSource {
  final Map<String, Object?> _values;

  StaticFlagsSource([Map<String, Object?> values = const {}])
      : _values = Map.of(values);

  @override
  Future<Map<String, Object?>> fetch() async => Map.of(_values);

  @override
  Stream<Map<String, Object?>>? changes() => null;

  @override
  Future<void> dispose() async {}
}
