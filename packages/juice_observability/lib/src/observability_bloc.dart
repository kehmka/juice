import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:juice/juice.dart';

import 'crash_reporter.dart';
import 'observability_config.dart';
import 'observability_events.dart';
import 'observability_state.dart';
import 'use_cases/add_breadcrumb_use_case.dart';
import 'use_cases/initialize_observability_use_case.dart';
import 'use_cases/record_error_use_case.dart';
import 'use_cases/set_context_use_case.dart';
import 'use_cases/set_enabled_use_case.dart';
import 'use_cases/set_user_use_case.dart';

/// Crash reporting + breadcrumbs, fanned out to one or more [CrashReporter]s.
///
/// Installs global error handlers (`FlutterError.onError` +
/// `PlatformDispatcher.onError`) so uncaught errors are captured automatically,
/// while preserving any handlers that were already set. Vendor-free — each
/// reporter is an adapter (Sentry, Crashlytics, …).
///
/// ```dart
/// final obs = ObservabilityBloc.withConfig(ObservabilityConfig(
///   reporters: [SentryCrashReporter(), if (kDebugMode) ConsoleCrashReporter()],
/// ));
/// obs.breadcrumb('opened checkout');
/// obs.recordError(e, st);
/// ```
class ObservabilityBloc extends JuiceBloc<ObservabilityState> {
  late ObservabilityConfig _config;

  FlutterExceptionHandler? _prevFlutterOnError;
  ErrorCallback? _prevPlatformOnError;
  bool _handlersInstalled = false;

  ObservabilityBloc()
      : super(
          ObservabilityState.initial,
          [
            () => UseCaseBuilder(
                typeOfEvent: InitializeObservabilityEvent,
                useCaseGenerator: () => InitializeObservabilityUseCase()),
            // sequential: the breadcrumb ring + error counter are
            // read-modify-writes of state; serializing same-type events makes
            // them race-free without bloc-side accumulators (juice ≥ 1.5.0).
            () => UseCaseBuilder(
                typeOfEvent: RecordErrorEvent,
                useCaseGenerator: () => RecordErrorUseCase(),
                concurrency: EventConcurrency.sequential),
            () => UseCaseBuilder(
                typeOfEvent: AddBreadcrumbEvent,
                useCaseGenerator: () => AddBreadcrumbUseCase(),
                concurrency: EventConcurrency.sequential),
            () => UseCaseBuilder(
                typeOfEvent: SetUserEvent,
                useCaseGenerator: () => SetUserUseCase()),
            () => UseCaseBuilder(
                typeOfEvent: SetContextEvent,
                useCaseGenerator: () => SetContextUseCase()),
            () => UseCaseBuilder(
                typeOfEvent: SetEnabledEvent,
                useCaseGenerator: () => SetEnabledUseCase()),
          ],
        );

  /// Create and initialize in one step.
  factory ObservabilityBloc.withConfig(ObservabilityConfig config) {
    final bloc = ObservabilityBloc();
    bloc.send(InitializeObservabilityEvent(config: config));
    return bloc;
  }

  void configure(ObservabilityConfig config) => _config = config;
  List<CrashReporter> get reporters => _config.reporters;
  int get maxBreadcrumbs => _config.maxBreadcrumbs;

  /// Install global error handlers, chaining any that were already set.
  void installHandlers() {
    if (_handlersInstalled) return;
    _handlersInstalled = true;

    _prevFlutterOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (!isClosed) send(RecordErrorEvent(details.exception, details.stack));
      _prevFlutterOnError?.call(details);
    };

    _prevPlatformOnError = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      if (!isClosed) send(RecordErrorEvent(error, stack, fatal: true));
      return _prevPlatformOnError?.call(error, stack) ?? true;
    };
  }

  /// Run [op] against every reporter, isolating failures.
  Future<void> fanOut(Future<void> Function(CrashReporter) op) async {
    for (final r in _config.reporters) {
      try {
        await op(r);
      } catch (_) {
        // A misbehaving reporter must not break the others.
      }
    }
  }

  // === Convenience API ===

  void recordError(Object error, [StackTrace? stack, bool fatal = false]) =>
      send(RecordErrorEvent(error, stack, fatal: fatal));
  void breadcrumb(String message, {String? category, Map<String, Object?> data = const {}}) =>
      send(AddBreadcrumbEvent(Breadcrumb(message, category: category, data: data)));
  void setUser(String? userId) => send(SetUserEvent(userId));
  void setContext(String key, Object? value) => send(SetContextEvent(key, value));
  void setEnabled(bool enabled) => send(SetEnabledEvent(enabled));

  @override
  Future<void> close() async {
    if (_handlersInstalled) {
      FlutterError.onError = _prevFlutterOnError;
      PlatformDispatcher.instance.onError = _prevPlatformOnError;
      _handlersInstalled = false;
    }
    for (final r in _config.reporters) {
      try {
        await r.dispose();
      } catch (_) {}
    }
    await super.close();
  }
}
