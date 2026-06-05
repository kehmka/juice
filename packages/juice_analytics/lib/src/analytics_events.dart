import 'package:juice/juice.dart';

import 'analytics_config.dart';

/// Base class for analytics events.
abstract class AnalyticsEvent extends EventBase {
  @override
  String toString() => runtimeType.toString();
}

/// Apply config.
class InitializeAnalyticsEvent extends AnalyticsEvent {
  final AnalyticsConfig config;
  InitializeAnalyticsEvent({required this.config});
}

/// Track a named event.
class LogEventEvent extends AnalyticsEvent {
  final String name;
  final Map<String, Object?> params;
  LogEventEvent(this.name, this.params);
}

/// Track a screen view.
class SetScreenEvent extends AnalyticsEvent {
  final String name;
  SetScreenEvent(this.name);
}

/// Identify (or clear) the current user.
class SetUserEvent extends AnalyticsEvent {
  final String? userId;
  final Map<String, Object?> traits;
  SetUserEvent(this.userId, this.traits);
}

/// Grant or revoke tracking consent.
class SetConsentEvent extends AnalyticsEvent {
  final bool enabled;
  SetConsentEvent(this.enabled);
}

/// Flush buffered events across sinks.
class FlushAnalyticsEvent extends AnalyticsEvent {}
