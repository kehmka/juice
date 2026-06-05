import 'package:juice/juice.dart';

import 'analytics_config.dart';
import 'analytics_events.dart';
import 'analytics_sink.dart';
import 'analytics_state.dart';
import 'use_cases/flush_analytics_use_case.dart';
import 'use_cases/initialize_analytics_use_case.dart';
import 'use_cases/log_event_use_case.dart';
import 'use_cases/set_consent_use_case.dart';
import 'use_cases/set_screen_use_case.dart';
import 'use_cases/set_user_use_case.dart';

/// Event and screen tracking, fanned out to one or more [AnalyticsSink]s behind
/// a consent gate.
///
/// When consent is off, events are **dropped** (counted), never buffered — so
/// nothing leaks once consent is later granted. The bloc never depends on a
/// vendor SDK; each sink is a vendor adapter.
///
/// ```dart
/// final analytics = AnalyticsBloc.withConfig(AnalyticsConfig(
///   sinks: [FirebaseAnalyticsSink(), if (kDebugMode) ConsoleAnalyticsSink()],
/// ));
/// analytics.log('checkout_started', {'cart': 3});
/// analytics.screen('Cart');
/// ```
class AnalyticsBloc extends JuiceBloc<AnalyticsState> {
  late AnalyticsConfig _config;

  AnalyticsBloc()
      : super(
          AnalyticsState.initial,
          [
            () => UseCaseBuilder(
                typeOfEvent: InitializeAnalyticsEvent,
                useCaseGenerator: () => InitializeAnalyticsUseCase()),
            () => UseCaseBuilder(
                typeOfEvent: LogEventEvent,
                useCaseGenerator: () => LogEventUseCase()),
            () => UseCaseBuilder(
                typeOfEvent: SetScreenEvent,
                useCaseGenerator: () => SetScreenUseCase()),
            () => UseCaseBuilder(
                typeOfEvent: SetUserEvent,
                useCaseGenerator: () => SetUserUseCase()),
            () => UseCaseBuilder(
                typeOfEvent: SetConsentEvent,
                useCaseGenerator: () => SetConsentUseCase()),
            () => UseCaseBuilder(
                typeOfEvent: FlushAnalyticsEvent,
                useCaseGenerator: () => FlushAnalyticsUseCase()),
          ],
        );

  /// Create and initialize in one step.
  factory AnalyticsBloc.withConfig(AnalyticsConfig config) {
    final bloc = AnalyticsBloc();
    bloc.send(InitializeAnalyticsEvent(config: config));
    return bloc;
  }

  void configure(AnalyticsConfig config) => _config = config;
  List<AnalyticsSink> get sinks => _config.sinks;

  /// Run [op] against every sink, isolating failures so one bad sink can't
  /// break the others.
  Future<void> fanOut(Future<void> Function(AnalyticsSink) op) async {
    for (final sink in _config.sinks) {
      try {
        await op(sink);
      } catch (_) {
        // A misbehaving sink must not break tracking for the rest.
      }
    }
  }

  // === Convenience API ===

  void log(String name, [Map<String, Object?> params = const {}]) =>
      send(LogEventEvent(name, params));
  void screen(String name) => send(SetScreenEvent(name));
  void setUser(String? userId, [Map<String, Object?> traits = const {}]) =>
      send(SetUserEvent(userId, traits));
  void setConsent(bool enabled) => send(SetConsentEvent(enabled));
  void flush() => send(FlushAnalyticsEvent());

  @override
  Future<void> close() async {
    for (final sink in _config.sinks) {
      try {
        await sink.dispose();
      } catch (_) {}
    }
    await super.close();
  }
}
