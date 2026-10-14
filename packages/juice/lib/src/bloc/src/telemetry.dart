import 'package:logger/web.dart' show Level;

/// What a [JuiceTelemetry] entry reports. Every kind names its wire form:
/// the `type` (and `action`) the entry carried as a context map before
/// 2.0.0, which [JuiceTelemetry.toMap] still produces for loggers and
/// tools that key on those strings.
enum JuiceTelemetryKind {
  // --- the use-case span
  /// A use case starts; the start of its span (`executionId`).
  useCaseStarted('use_case_execution'),

  /// A use case returned; closes the span with `elapsedMicros`.
  useCaseCompleted('use_case_completed'),

  /// A use case threw; closes the span with the error.
  useCaseFailed('use_case_error', level: Level.error),

  /// A `sequential` run failed outside the executor (a throwing `onError`).
  sequentialRunFailed('use_case_error', level: Level.error),

  /// A `restartable` run was superseded by a newer same-type event.
  useCaseSuperseded('use_case_superseded'),

  /// Superseding a run threw (a throwing `cancel()`, logger or binding).
  supersedeFailed('use_case_superseded', action: 'error', level: Level.error),

  // --- emissions
  /// A status reached the stream.
  stateEmitted('state_emission'),

  /// `skipIfSame` suppressed an emission equal to the current state.
  emissionSkipped('state_emission_skipped'),

  /// The restartable fence dropped an emission of a superseded run.
  emissionSuperseded('state_emission_superseded'),

  /// An in-flight use case emitted after its bloc closed; dropped.
  emissionAfterClose('emission_after_close', level: Level.warning),

  // --- the bloc's lifecycle
  /// A `send` on a closed or closing bloc was refused.
  eventIgnored('bloc_lifecycle', action: 'event_ignored', level: Level.warning),

  /// A bloc's `close()` started (from the bloc, or from the scope).
  blocClosing('bloc_lifecycle', action: 'close'),

  /// `BlocScope.register`.
  blocRegistered('bloc_lifecycle', action: 'register'),

  /// The scope created a bloc instance.
  blocCreated('bloc_lifecycle', action: 'create'),

  /// A lease was acquired (`leaseCount` after).
  leaseAcquired('bloc_lifecycle', action: 'lease_acquire'),

  /// A lease was released (`leaseCount` after).
  leaseReleased('bloc_lifecycle', action: 'lease_release'),

  /// A lease on a since-replaced instance was released; ignored.
  staleLeaseReleased('bloc_lifecycle', action: 'lease_release_stale'),

  /// A feature scope ended (`count` blocs).
  featureScopeEnded('bloc_lifecycle', action: 'end_feature'),

  /// `BlocScope.endAll`.
  allBlocsEnded('bloc_lifecycle', action: 'end_all'),

  /// A bloc's `close()` threw; the scope still cleared its entry.
  blocCloseFailed('bloc_close_error', level: Level.error),

  // --- errors
  /// `JuiceBloc.onError`: an error reached the bloc's error hook.
  blocError('bloc_error', level: Level.error),

  /// The configured `BlocErrorHandler` threw.
  errorHandlerFailed('error_handler_error', level: Level.error),

  /// An event no use case handles was sent.
  unhandledEvent('unhandled_event', level: Level.error),

  /// An aviator's navigation threw.
  aviatorError('aviator_error', level: Level.error),

  // --- stream bindings
  /// `bindStream` listened.
  streamBound('stream_binding', action: 'bind'),

  /// A bound stream ended.
  streamBindingDone('stream_binding', action: 'done'),

  /// `bindStream` refused (the bloc closing, the run superseded): `reason`.
  streamBindingRefused('stream_binding', action: 'refused'),

  /// A bound stream errored with no `onError` of its own.
  streamBindingError('stream_binding', action: 'error', level: Level.error),

  /// A binding's `onData` / `onError` / `onDone` threw: `callback`.
  streamBindingCallbackError('stream_binding',
      action: 'callback_error', level: Level.error),

  /// A binding's cancel threw: `reason` says where.
  streamBindingCancelError('stream_binding',
      action: 'cancel_error', level: Level.error),

  // --- builders and relays
  /// A retry was abandoned because the bloc closed (`attempt`).
  retryAbandoned('retry_abandoned'),

  /// An `EventSubscription` subscribed to its source.
  eventSubscriptionInitialized('event_subscription', action: 'initialize'),

  /// An `EventSubscription` forwarded a source event as a local one.
  eventSubscriptionTriggered('event_subscription', action: 'trigger'),

  /// An `EventSubscription` closed.
  eventSubscriptionClosed('event_subscription', action: 'close'),

  /// Leak detection was enabled.
  leakDetectionEnabled('leak_detection', action: 'enable');

  const JuiceTelemetryKind(this.type, {this.action, this.level = Level.info});

  /// The wire `type` (the pre-2.0 context key).
  final String type;

  /// The wire `action`, for kinds that had one.
  final String? action;

  /// The level of an entry of this kind that carries no error.
  final Level level;
}

/// One framework telemetry entry: a typed, immutable record the framework
/// hands to [JuiceLogger.record] in place of a message plus a
/// `Map<String, dynamic>` context. One allocation per entry, fields read
/// by name; nothing is stringified until a logger prints or ships it.
///
/// Values are LIVE objects — [state] is the emitted state, [groups] the
/// caller's set, [error] the error — so a logger that drops the entry pays
/// nothing. Stringify only what you keep, and do not retain an entry: it
/// pins the state it names.
///
/// [toMap] renders the pre-2.0 context map (`type`, `action`, every set
/// field) for loggers and tools that key on those strings.
final class JuiceTelemetry {
  const JuiceTelemetry(
    this.kind, {
    Level? level,
    this.bloc,
    this.event,
    this.useCase,
    this.executionId,
    this.elapsedMicros,
    this.superseded = false,
    this.status,
    this.state,
    this.groups,
    this.key,
    this.reason,
    this.callback,
    this.error,
    this.stackTrace,
    this.cancellable,
    this.attempt,
    this.aviator,
    this.lifecycle,
    this.scope,
    this.leaseCount,
    this.count,
    this.sourceBloc,
    this.sourceEvent,
    this.localEvent,
  }) : _level = level;

  /// What happened.
  final JuiceTelemetryKind kind;

  final Level? _level;

  /// The entry's level: an explicit one, else the kind's. A failure
  /// emission carries an [error] and is still an emission at the kind's
  /// level; the error kinds declare [Level.error].
  Level get level => _level ?? kind.level;

  /// Whether this is an error entry (an error kind, or an explicit error
  /// level) — the fail-loud path, delivered whatever the floor.
  bool get isError => level.value >= Level.error.value;

  /// The bloc's type name.
  final String? bloc;

  /// The event's type name.
  final String? event;

  /// The use case's type name.
  final String? useCase;

  /// The span id shared by a use case's start and end entries.
  final int? executionId;

  /// The span's duration, on the end entry.
  final int? elapsedMicros;

  /// Whether the run had been superseded when its span closed.
  final bool superseded;

  /// The emission's status name (`update`, `waiting`, `failure`, `cancel`,
  /// `event`, `navigate`).
  final String? status;

  /// The emitted state (live object).
  final Object? state;

  /// The emission's rebuild groups (the caller's set).
  final Set<String>? groups;

  /// A stream binding's key.
  final String? key;

  /// Why: a refusal's reason, a cancel's site, an ignored event's cause.
  final String? reason;

  /// Which binding callback threw (`onData`, `onError`, `onDone`).
  final String? callback;

  /// The error, for error entries.
  final Object? error;

  /// The error's stack trace.
  final StackTrace? stackTrace;

  /// Whether a superseded event was a `CancellableEvent`.
  final bool? cancellable;

  /// A retry attempt number.
  final int? attempt;

  /// An aviator's name.
  final String? aviator;

  /// A registration's lifecycle.
  final String? lifecycle;

  /// A scope's name.
  final String? scope;

  /// A lease count after the change.
  final int? leaseCount;

  /// A count: bindings cancelled at close, blocs ended with a scope.
  final int? count;

  /// An `EventSubscription`'s source bloc type name.
  final String? sourceBloc;

  /// An `EventSubscription`'s source event type name.
  final String? sourceEvent;

  /// An `EventSubscription`'s local event type name.
  final String? localEvent;

  /// The human line for this entry — built only when read.
  String get message => switch (kind) {
        JuiceTelemetryKind.useCaseStarted => 'Executing use case',
        JuiceTelemetryKind.useCaseCompleted => 'Use case completed',
        JuiceTelemetryKind.useCaseFailed => 'Use case execution failed',
        JuiceTelemetryKind.sequentialRunFailed =>
          'Sequential run failed outside the executor',
        JuiceTelemetryKind.useCaseSuperseded => 'Use case superseded',
        JuiceTelemetryKind.supersedeFailed => 'Error while superseding a run',
        JuiceTelemetryKind.stateEmitted => 'Emitting $status',
        JuiceTelemetryKind.emissionSkipped =>
          'Skipping duplicate state emission',
        JuiceTelemetryKind.emissionSuperseded =>
          'Emission dropped: use case superseded',
        JuiceTelemetryKind.emissionAfterClose => 'Emission after close dropped',
        JuiceTelemetryKind.eventIgnored => 'Event ignored: $reason',
        JuiceTelemetryKind.blocClosing => 'Closing bloc',
        JuiceTelemetryKind.blocRegistered => 'Bloc registered',
        JuiceTelemetryKind.blocCreated => 'Bloc instance created',
        JuiceTelemetryKind.leaseAcquired => 'Lease acquired',
        JuiceTelemetryKind.leaseReleased => 'Lease released',
        JuiceTelemetryKind.staleLeaseReleased => 'Stale lease released',
        JuiceTelemetryKind.featureScopeEnded => 'Feature scope ended',
        JuiceTelemetryKind.allBlocsEnded => 'All blocs ended',
        JuiceTelemetryKind.blocCloseFailed => 'Bloc close failed',
        JuiceTelemetryKind.blocError => 'Bloc error',
        JuiceTelemetryKind.errorHandlerFailed => 'Error in custom errorHandler',
        JuiceTelemetryKind.unhandledEvent =>
          'No use case registered for $event',
        JuiceTelemetryKind.aviatorError => 'Aviator navigation failed',
        JuiceTelemetryKind.streamBound => 'Stream bound',
        JuiceTelemetryKind.streamBindingDone => 'Stream binding done',
        JuiceTelemetryKind.streamBindingRefused =>
          'Stream binding refused: $reason',
        JuiceTelemetryKind.streamBindingError => 'Stream binding error',
        JuiceTelemetryKind.streamBindingCallbackError =>
          'Stream binding $callback threw',
        JuiceTelemetryKind.streamBindingCancelError =>
          'Stream binding cancel failed $reason',
        JuiceTelemetryKind.retryAbandoned => 'Retry abandoned: bloc closed',
        JuiceTelemetryKind.eventSubscriptionInitialized =>
          'EventSubscription initialized',
        JuiceTelemetryKind.eventSubscriptionTriggered =>
          'EventSubscription triggered',
        JuiceTelemetryKind.eventSubscriptionClosed =>
          'EventSubscription closed',
        JuiceTelemetryKind.leakDetectionEnabled => 'Leak detection enabled',
      };

  /// The entry as the context map it was before 2.0.0: `type`, `action`
  /// and every field that is set, values live. For loggers and tools that
  /// key on the strings; built on demand, never by the framework.
  Map<String, Object?> toMap() => {
        'type': kind.type,
        if (kind.action != null) 'action': kind.action,
        if (bloc != null) 'bloc': bloc,
        if (event != null) 'event': event,
        if (useCase != null) 'useCase': useCase,
        if (executionId != null) 'executionId': executionId,
        if (elapsedMicros != null) 'elapsedMicros': elapsedMicros,
        if (superseded) 'superseded': true,
        if (status != null) 'status': status,
        if (state != null) 'state': state,
        if (groups != null) 'groups': groups,
        if (key != null) 'key': key,
        if (reason != null) 'reason': reason,
        if (callback != null) 'callback': callback,
        if (error != null) 'error': error,
        if (cancellable != null) 'cancellable': cancellable,
        if (attempt != null) 'attempt': attempt,
        if (aviator != null) 'aviator': aviator,
        if (lifecycle != null) 'lifecycle': lifecycle,
        if (scope != null) 'scope': scope,
        if (leaseCount != null) 'leaseCount': leaseCount,
        if (count != null) 'count': count,
        if (sourceBloc != null) 'sourceBloc': sourceBloc,
        if (sourceEvent != null) 'sourceEvent': sourceEvent,
        if (localEvent != null) 'localEvent': localEvent,
      };

  @override
  String toString() => '$message ${toMap()}';
}
