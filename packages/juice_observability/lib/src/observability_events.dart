import 'package:juice/juice.dart';

import 'crash_reporter.dart';
import 'observability_config.dart';

/// Base class for observability events.
abstract class ObservabilityEvent extends EventBase {
  @override
  String toString() => runtimeType.toString();
}

/// Apply config; install global error handlers if configured.
class InitializeObservabilityEvent extends ObservabilityEvent {
  final ObservabilityConfig config;
  InitializeObservabilityEvent({required this.config});
}

/// Record an error.
class RecordErrorEvent extends ObservabilityEvent {
  final Object error;
  final StackTrace? stack;
  final bool fatal;
  RecordErrorEvent(this.error, this.stack, {this.fatal = false});
}

/// Add a breadcrumb.
class AddBreadcrumbEvent extends ObservabilityEvent {
  final Breadcrumb crumb;
  AddBreadcrumbEvent(this.crumb);
}

/// Identify (or clear) the current user.
class SetUserEvent extends ObservabilityEvent {
  final String? userId;
  SetUserEvent(this.userId);
}

/// Set a custom context key/value.
class SetContextEvent extends ObservabilityEvent {
  final String key;
  final Object? value;
  SetContextEvent(this.key, this.value);
}

/// Enable or disable capture/reporting.
class SetEnabledEvent extends ObservabilityEvent {
  final bool enabled;
  SetEnabledEvent(this.enabled);
}
