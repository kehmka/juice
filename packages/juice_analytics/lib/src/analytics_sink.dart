/// A destination for analytics — a vendor adapter (Firebase, Mixpanel, Segment,
/// PostHog, …). The bloc fans events out to one or more of these; it never
/// depends on a vendor SDK.
///
/// All methods should swallow nothing important but must not throw on the hot
/// path — a misbehaving sink shouldn't break tracking for the others (the bloc
/// isolates each sink).
abstract class AnalyticsSink {
  /// Record a named event with optional parameters.
  Future<void> logEvent(String name, Map<String, Object?> params);

  /// Record a screen / route view.
  Future<void> setScreen(String name);

  /// Associate (or clear) the current user and optional traits.
  Future<void> setUser(String? userId, Map<String, Object?> traits);

  /// Flush any buffered events (no-op if the vendor batches internally).
  Future<void> flush();

  /// Release resources.
  Future<void> dispose();
}

/// Prints events to the console — handy in development and tests.
class ConsoleAnalyticsSink implements AnalyticsSink {
  final void Function(String) _out;
  ConsoleAnalyticsSink([void Function(String)? out]) : _out = out ?? print;

  @override
  Future<void> logEvent(String name, Map<String, Object?> params) async =>
      _out('[analytics] $name $params');
  @override
  Future<void> setScreen(String name) async => _out('[analytics] screen: $name');
  @override
  Future<void> setUser(String? userId, Map<String, Object?> traits) async =>
      _out('[analytics] user: $userId $traits');
  @override
  Future<void> flush() async {}
  @override
  Future<void> dispose() async {}
}

/// Discards everything — a safe default when no provider is wired.
class NoopAnalyticsSink implements AnalyticsSink {
  const NoopAnalyticsSink();
  @override
  Future<void> logEvent(String name, Map<String, Object?> params) async {}
  @override
  Future<void> setScreen(String name) async {}
  @override
  Future<void> setUser(String? userId, Map<String, Object?> traits) async {}
  @override
  Future<void> flush() async {}
  @override
  Future<void> dispose() async {}
}
