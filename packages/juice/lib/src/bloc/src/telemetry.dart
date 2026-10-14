import 'package:logger/web.dart' show Level;

import 'lifecycle/bloc_lifecycle.dart';

/// What an emission is, as the telemetry names it. [wire] is the `status`
/// value an entry carries on the wire.
enum EmissionKind {
  /// `emitUpdate`.
  update('update'),

  /// `emitWaiting`.
  waiting('waiting'),

  /// `emitFailure`.
  failure('failure'),

  /// `emitCancel`.
  cancel('cancel'),

  /// `emitEvent` — the current status re-emitted carrying an event.
  event('event'),

  /// A navigation (only as the thing a fence dropped).
  navigate('navigate');

  const EmissionKind(this.wire);

  /// The wire value.
  final String wire;
}

/// What a [JuiceTelemetry] entry reports. Every kind names its wire form —
/// [wireType] and [wireAction], the `type` and `action` keys
/// [JuiceTelemetry.toMap] emits — its [level], and its [message].
enum JuiceTelemetryKind {
  // --- the use-case span
  /// A use case is about to execute; opens the span (`executionId`).
  useCaseStarted('use_case_execution', 'Executing use case'),

  /// A use case returned; closes the span with `elapsedMicros`.
  useCaseCompleted('use_case_completed', 'Use case completed'),

  /// A use case (or its generator) threw; closes the span with the error.
  useCaseFailed('use_case_error', 'Use case execution failed',
      level: Level.error),

  /// A `sequential` run's failure escaped the executor (an `onError`
  /// override that throws); the queue goes on. No span: it has no
  /// `executionId`.
  sequentialRunFailed(
      'sequential_run_error', 'Sequential run failed outside the executor',
      level: Level.error),

  /// A `restartable` run was superseded by a newer same-type event.
  useCaseSuperseded('use_case_superseded', 'Use case superseded'),

  /// Superseding a run threw (a throwing `cancel()`, logger or binding
  /// cancel); the new run still starts.
  supersedeFailed('supersede_error', 'Error while superseding a run',
      level: Level.error),

  // --- emissions
  /// A status is being put on the stream: `status`, `state`, `groups`;
  /// `error` and `stackTrace` on a failure.
  stateEmitted('state_emission', 'State emitted'),

  /// `emitUpdate(skipIfSame: true)` found `newState == state`.
  emissionSkipped('state_emission_skipped', 'Duplicate emission skipped'),

  /// The restartable fence dropped an emission or navigation of a
  /// superseded run (`status`).
  emissionSuperseded(
      'state_emission_superseded', 'Emission dropped: use case superseded'),

  /// An in-flight use case emitted after its bloc closed; dropped.
  emissionAfterClose('emission_after_close', 'Emission after close dropped',
      level: Level.warning),

  // --- the bloc's lifecycle
  /// A `send` on a closed or closing bloc was refused (`reason`).
  eventIgnored('bloc_lifecycle', 'Event ignored',
      action: 'event_ignored', level: Level.warning),

  /// A bloc's `close()` started (`bindingCount` bindings to cancel).
  blocCloseStarted('bloc_lifecycle', 'Bloc closing', action: 'close'),

  /// `BlocScope.register` registered a new type (a repeat registration
  /// records nothing).
  blocRegistered('bloc_lifecycle', 'Bloc registered', action: 'register'),

  /// The scope ran a factory.
  blocCreated('bloc_lifecycle', 'Bloc instance created', action: 'create'),

  /// A lease was taken (`leaseCount` after).
  leaseAcquired('bloc_lifecycle', 'Lease acquired', action: 'lease_acquire'),

  /// A lease was released (`leaseCount` after).
  leaseReleased('bloc_lifecycle', 'Lease released', action: 'lease_release'),

  /// A lease on an instance the scope has since replaced was released;
  /// ignored.
  staleLeaseReleased('bloc_lifecycle', 'Stale lease released',
      action: 'lease_release_stale'),

  /// `BlocScope.get` on a bloc registered `leased` — `lease` is the API for
  /// it. (Debug builds assert instead.)
  leasedBlocGot('bloc_lifecycle', 'get() on a leased bloc; use lease()',
      action: 'get_on_leased', level: Level.warning),

  /// A feature scope ended its blocs (`blocCount` managed).
  featureScopeEnded('bloc_lifecycle', 'Feature scope ended',
      action: 'end_feature'),

  /// `BlocScope.endAll` closed every bloc.
  allBlocsEnded('bloc_lifecycle', 'All blocs ended', action: 'end_all'),

  /// A bloc's `close()` threw; the scope still cleared its entry and
  /// rethrows.
  blocCloseFailed('bloc_close_error', 'Bloc close failed', level: Level.error),

  // --- errors
  /// `JuiceBloc.onError`: an error reached the bloc's error hook.
  blocError('bloc_error', 'Bloc error', level: Level.error),

  /// The configured `BlocErrorHandler` threw.
  errorHandlerFailed('error_handler_error', 'Error in custom errorHandler',
      level: Level.error),

  /// An event no use case handles was sent (`event`).
  unhandledEvent('unhandled_event', 'No use case registered for the event',
      level: Level.error),

  /// An aviator's navigation threw (`aviator`).
  aviatorFailed('aviator_error', 'Aviator navigation failed',
      level: Level.error),

  // --- stream bindings
  /// `bindStream` listened (`key`).
  streamBindingStarted('stream_binding', 'Stream bound', action: 'bind'),

  /// A bound stream ended.
  streamBindingDone('stream_binding', 'Stream binding done', action: 'done'),

  /// `bindStream` on a closed or closing bloc returned an inert binding
  /// (`reason`).
  streamBindingRefused(
      'stream_binding', 'Stream binding refused: the bloc is closing',
      action: 'refused', level: Level.warning),

  /// `bindStream` from a superseded restartable run returned an inert
  /// binding.
  streamBindingSuperseded(
      'stream_binding', 'Stream binding refused: the run was superseded',
      action: 'refused'),

  /// A bound stream errored and the binding has no `onError` of its own.
  streamBindingError('stream_binding', 'Stream binding error',
      action: 'error', level: Level.error),

  /// A binding's `onData` / `onError` / `onDone` threw (`callback`).
  streamBindingCallbackFailed('stream_binding', 'Stream binding callback threw',
      action: 'callback_error', level: Level.error),

  /// A subscription's cancel threw (`site` says where).
  streamBindingCancelFailed('stream_binding', 'Stream binding cancel failed',
      action: 'cancel_error', level: Level.error),

  // --- builders and relays
  /// `RetryableUseCaseBuilder` will retry after a backoff (`attempt`, the
  /// `error` that caused it).
  retryScheduled('retry_scheduled', 'Retrying operation'),

  /// `RetryableUseCaseBuilder` is out of attempts (`attempt` = attempts
  /// made); the final failure is emitted.
  retryExhausted('retry_exhausted', 'Retries exhausted'),

  /// `RetryableUseCaseBuilder` stopped because the bloc closed during a
  /// backoff (`attempt`).
  retryAbandoned('retry_abandoned', 'Retry abandoned: bloc closed'),

  /// An `EventSubscription` subscribed to its source.
  eventSubscriptionInitialized(
      'event_subscription', 'EventSubscription initialized',
      action: 'initialize'),

  /// A source event was forwarded as a local one.
  eventSubscriptionTriggered(
      'event_subscription', 'EventSubscription triggered',
      action: 'trigger'),

  /// The subscription closed.
  eventSubscriptionClosed('event_subscription', 'EventSubscription closed',
      action: 'close'),

  /// An `EventSubscription` failed (`site`: `initialize`, `transform` or
  /// `stream`). An `initialize` failure is also thrown to the caller.
  eventSubscriptionFailed('event_subscription', 'EventSubscription failed',
      action: 'error', level: Level.error),

  /// A `StateRelay` / `StatusRelay` failed (`relay`, `site`: `initialize`,
  /// `transform` or `stream`). An `initialize` failure is also thrown.
  relayFailed('relay_error', 'Relay failed', level: Level.error),

  /// `BlocScope.enableLeakDetection`.
  leakDetectionEnabled('leak_detection', 'Leak detection enabled',
      action: 'enable');

  const JuiceTelemetryKind(this.wireType, this.message,
      {String? action, this.level = Level.info})
      : wireAction = action;

  /// The wire `type`.
  final String wireType;

  /// The wire `action`, for kinds that have one.
  final String? wireAction;

  /// The entry's level. Error kinds are [Level.error].
  final Level level;

  /// The human line. Constant: the facts are the entry's fields.
  final String message;

  /// Whether entries of this kind are errors — the fail-loud path.
  bool get isError => level.value >= Level.error.value;
}

/// One framework telemetry entry: the typed record the framework hands to
/// [JuiceLogger.record] in place of a message plus a `Map<String, dynamic>`
/// context. One allocation per entry; fields read by name; nothing is
/// stringified until a logger prints or ships it.
///
/// Fields are LIVE objects — [state] is the emitted state, [groups] the
/// caller's set, [error] the error — so a logger that drops the entry pays
/// nothing. Stringify only what you keep, and do not retain an entry: it
/// pins the state it names.
///
/// Which fields a kind sets is in [JuiceTelemetryKind]'s doc and in
/// `doc/TELEMETRY.md`. Every error kind carries [error] (and a
/// [stackTrace] where one exists). [toMap] renders the pre-2.0 context map
/// for loggers and tools that key on those strings.
final class JuiceTelemetry {
  /// Creates an entry of [kind] with the fields that kind sets.
  const JuiceTelemetry(
    this.kind, {
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
    this.site,
    this.callback,
    this.error,
    this.stackTrace,
    this.cancellable,
    this.attempt,
    this.aviator,
    this.lifecycle,
    this.scope,
    this.leaseCount,
    this.bindingCount,
    this.blocCount,
    this.sourceBloc,
    this.sourceEvent,
    this.localEvent,
    this.destBloc,
    this.relay,
  });

  /// What happened.
  final JuiceTelemetryKind kind;

  /// The kind's level.
  Level get level => kind.level;

  /// Whether this is an error entry: an error kind, always carrying
  /// [error]. Error entries, [JuiceTelemetryKind.emissionAfterClose],
  /// [JuiceTelemetryKind.eventIgnored], [JuiceTelemetryKind.leasedBlocGot]
  /// and a failure [JuiceTelemetryKind.stateEmitted] are recorded whatever
  /// the telemetry floor says; every other kind is built only when
  /// `JuiceLoggerConfig.logs(level)` keeps its level.
  bool get isError => kind.isError;

  /// The human line for this entry (the kind's).
  String get message => kind.message;

  /// The bloc's type name.
  final String? bloc;

  /// The event's type name.
  final String? event;

  /// The use case's type name (the builder's, when the generator threw).
  final String? useCase;

  /// The span id shared by a use case's start and end entries.
  final int? executionId;

  /// The span's duration, when the span was being timed (the chatter was
  /// on when the use case started).
  final int? elapsedMicros;

  /// Whether the run had been superseded when its span closed.
  final bool superseded;

  /// The emission's kind.
  final EmissionKind? status;

  /// The emitted state (live object).
  final Object? state;

  /// The emission's rebuild groups (the caller's set; null means every
  /// widget).
  final Set<String>? groups;

  /// A stream binding's key.
  final String? key;

  /// Why: a refusal's or an ignored event's cause (`bloc is closed`,
  /// `bloc is closing`, `run superseded`).
  final String? reason;

  /// Where: a cancel's site (`at unbind`, `at close`, `at supersede`,
  /// `on error`); a relay's or subscription's failing step (`initialize`,
  /// `transform`, `stream`).
  final String? site;

  /// Which binding callback threw (`onData`, `onError`, `onDone`).
  final String? callback;

  /// The error, on every error kind, on a failure emission and on a
  /// scheduled retry.
  final Object? error;

  /// The error's stack trace, where one exists.
  final StackTrace? stackTrace;

  /// Whether a superseded event was a `CancellableEvent`.
  final bool? cancellable;

  /// A retry's attempt number (on `retryExhausted`, the attempts made).
  final int? attempt;

  /// An aviator's name.
  final String? aviator;

  /// A registration's lifecycle.
  final BlocLifecycle? lifecycle;

  /// A scope's key (`global` when none), or a feature scope's name.
  final String? scope;

  /// A lease count after the change.
  final int? leaseCount;

  /// Bindings a closing bloc cancels.
  final int? bindingCount;

  /// Blocs a feature scope managed when it ended.
  final int? blocCount;

  /// A subscription's or relay's source bloc type name.
  final String? sourceBloc;

  /// A subscription's source event type name.
  final String? sourceEvent;

  /// A subscription's local event type name.
  final String? localEvent;

  /// A relay's destination bloc type name.
  final String? destBloc;

  /// A relay's type name (`StateRelay`, `StatusRelay`).
  final String? relay;

  /// The entry as the context map it was before 2.0.0 — `type`, `action`
  /// and every field that is set, under the keys the 1.x entries used
  /// (`streamBindings`, `blocsEnded`), values live. For loggers and tools
  /// that key on the strings; built on demand, never by the framework.
  Map<String, Object?> toMap() => {
        'type': kind.wireType,
        if (kind.wireAction != null) 'action': kind.wireAction,
        if (bloc != null) 'bloc': bloc,
        if (event != null) 'event': event,
        if (useCase != null) 'useCase': useCase,
        if (executionId != null) 'executionId': executionId,
        if (elapsedMicros != null) 'elapsedMicros': elapsedMicros,
        if (superseded) 'superseded': true,
        if (status != null) 'status': status!.wire,
        if (state != null) 'state': state,
        if (groups != null) 'groups': groups,
        if (key != null) 'key': key,
        if (reason != null) 'reason': reason,
        if (site != null) 'site': site,
        if (callback != null) 'callback': callback,
        if (error != null) 'error': error,
        if (cancellable != null) 'cancellable': cancellable,
        if (attempt != null) 'attempt': attempt,
        if (aviator != null) 'aviator': aviator,
        if (lifecycle != null) 'lifecycle': lifecycle!.name,
        if (scope != null) 'scope': scope,
        if (leaseCount != null) 'leaseCount': leaseCount,
        if (bindingCount != null) 'streamBindings': bindingCount,
        if (blocCount != null) 'blocsEnded': blocCount,
        if (sourceBloc != null) 'sourceBloc': sourceBloc,
        if (sourceEvent != null) 'sourceEvent': sourceEvent,
        if (localEvent != null) 'localEvent': localEvent,
        if (destBloc != null) 'destBloc': destBloc,
        if (relay != null) 'relay': relay,
      };
}
