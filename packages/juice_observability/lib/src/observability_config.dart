import 'crash_reporter.dart';

/// Configures an `ObservabilityBloc`.
class ObservabilityConfig {
  /// Destinations for reports + breadcrumbs (e.g. a Sentry reporter + a debug
  /// reporter). Defaults to a single [NoopCrashReporter].
  final List<CrashReporter> reporters;

  /// Install global handlers (`FlutterError.onError` +
  /// `PlatformDispatcher.instance.onError`) to auto-capture uncaught errors.
  final bool captureUncaught;

  /// Max breadcrumbs retained (oldest dropped). 0 disables breadcrumbs.
  final int maxBreadcrumbs;

  ObservabilityConfig({
    List<CrashReporter>? reporters,
    this.captureUncaught = true,
    this.maxBreadcrumbs = 50,
  }) : reporters = reporters ?? const [NoopCrashReporter()];
}
