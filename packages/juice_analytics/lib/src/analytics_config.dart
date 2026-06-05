import 'analytics_sink.dart';

/// Configures an `AnalyticsBloc`.
class AnalyticsConfig {
  /// Destinations to fan events out to (e.g. a Firebase sink + a debug sink).
  /// Defaults to a single [NoopAnalyticsSink].
  final List<AnalyticsSink> sinks;

  /// Whether tracking starts enabled. Set false to require explicit consent
  /// first (events are dropped until `setConsent(true)`).
  final bool initiallyEnabled;

  AnalyticsConfig({
    List<AnalyticsSink>? sinks,
    this.initiallyEnabled = true,
  }) : sinks = sinks ?? const [NoopAnalyticsSink()];
}
