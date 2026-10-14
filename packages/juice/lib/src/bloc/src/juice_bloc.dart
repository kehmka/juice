import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:logger/web.dart' show Level;

import 'bloc_state.dart';
import 'bloc_event.dart';
import 'stream_status.dart';
import 'juice_logger.dart';
import 'bloc_use_case.dart';
import 'bloc_error_handler.dart';
import 'cancellable_event.dart';
import 'core/event_concurrency.dart';
import 'core/restartable_run.dart';
import 'stream_binding.dart';
import 'telemetry.dart';
import 'core/type_names.dart';
import 'use_case_builders/use_case_builder.dart';
import 'aviators/aviator.dart';
import 'core/state_manager.dart';
import 'core/event_dispatcher.dart';
import 'core/use_case_registry.dart';
import 'core/use_case_executor.dart';
import 'core/status_emitter.dart';
import 'core/aviator_manager.dart';
import 'bloc_interfaces.dart';

/// A bloc that manages state through use cases.
///
/// JuiceBloc provides structured state management by routing events to
/// dedicated use cases, which encapsulate business logic and emit state
/// changes. It uses composition of focused components rather than deep
/// inheritance.
///
/// Example:
/// ```dart
/// class CounterBloc extends JuiceBloc<CounterState> {
///   CounterBloc() : super(
///     CounterState(count: 0),
///     [
///       () => UseCaseBuilder(
///         typeOfEvent: IncrementEvent,
///         useCaseGenerator: () => IncrementUseCase(),
///         concurrency: EventConcurrency.sequential,
///       ),
///     ],
///   );
/// }
/// ```
class JuiceBloc<TState extends BlocState>
    implements
        StateStreamableSource<StreamStatus<TState>>,
        Emittable<StreamStatus<TState>>,
        ErrorSink {
  /// Creates a JuiceBloc with initial state and use cases.
  ///
  /// [initialState] - The initial state of the bloc
  /// [useCases] - List of use case builders that handle events
  /// [aviatorBuilders] - List of navigation builders (optional)
  /// [customLogger] - Optional custom logger implementation
  /// [errorHandler] - Custom error handler, defaults to BlocErrorHandler
  JuiceBloc(
    TState initialState,
    List<UseCaseBuilderGenerator> useCases, [
    List<AviatorBuilder> aviatorBuilders = const [],
    JuiceLogger? customLogger,
    BlocErrorHandler errorHandler = const BlocErrorHandler(),
  ])  : _logger = customLogger ?? JuiceLoggerConfig.logger,
        _errorHandler = errorHandler,
        _stateManager = StateManager(
          StreamStatus.updating(initialState, initialState, null),
        ) {
    _statusEmitter = StatusEmitter(
      stateManager: _stateManager,
      logger: _logger,
      blocName: runtimeType.toString(),
    );

    _useCaseExecutor = UseCaseExecutor<JuiceBloc<TState>, TState>(
      contextFactory: _createContext,
      onError: _handleUseCaseError,
      logger: _logger,
    );

    _dispatcher = EventDispatcher<EventBase>(
      onUnhandledEvent: _handleUnhandledEvent,
      onSuperseded: _cancelBindingsOf,
      logger: _logger,
    );

    _initialize(useCases, aviatorBuilders);
  }

  // ============================================================
  // Components
  // ============================================================

  final StateManager<StreamStatus<TState>> _stateManager;
  late final StatusEmitter<TState> _statusEmitter;
  late final EventDispatcher<EventBase> _dispatcher;
  late final UseCaseExecutor<JuiceBloc<TState>, TState> _useCaseExecutor;
  final UseCaseRegistry _useCaseRegistry = UseCaseRegistry();
  final AviatorManager _aviatorManager = AviatorManager();

  // ============================================================
  // Configuration
  // ============================================================

  /// Internal logger instance
  final JuiceLogger _logger;

  /// This bloc's type name, for telemetry.
  late final String _name = typeName(runtimeType);

  final BlocErrorHandler _errorHandler;

  // ============================================================
  // Stream bindings
  // ============================================================

  /// Every live binding; keyed ones are also in [_keyedBindings].
  final Set<StreamBinding<dynamic>> _bindings = {};
  final Map<String, StreamBinding<dynamic>> _keyedBindings = {};

  /// Listen to [stream] for as long as this bloc lives.
  ///
  /// [onData] runs for every item while the bloc is open — never once it
  /// is closing — typically to `send` an event per item. The bloc owns the
  /// subscription: it is cancelled at the start of [close], before the use
  /// cases close, so no bloc needs a `StreamSubscription` field, an
  /// `isClosed` guard, or a manual cancel in its own `close()`.
  ///
  /// [key] makes the start idempotent: a later `bindStream` with the same
  /// key REPLACES the earlier binding (the earlier one is cancelled first),
  /// and [unbind] stops it by name. Anonymous bindings are stopped through
  /// the returned [StreamBinding.cancel].
  ///
  /// Errors are loud. A stream error goes to [onError] if given, otherwise
  /// to the bloc's [JuiceBloc.onError] (logged as `bloc_error` and passed
  /// to the error handler). Either way the binding is then cancelled unless
  /// [cancelOnError] is false — the same contract as `Stream.listen`. An
  /// error THROWN BY [onData] goes to the bloc's error handler too, and the
  /// binding stays active: the stream is not broken, that item was.
  ///
  /// [onDone] runs when the stream ends; the binding is then inactive.
  ///
  /// Called on a closing or closed bloc, it logs `stream_binding` /
  /// `refused` and returns an inert binding — the same fence `send` applies
  /// to a late event — rather than listening to a stream nobody will
  /// cancel.
  StreamBinding<T> bindStream<T>(
    Stream<T> stream,
    void Function(T item) onData, {
    String? key,
    void Function(Object error, StackTrace stackTrace)? onError,
    void Function()? onDone,
    bool cancelOnError = true,
  }) {
    if (isClosing) {
      return _refuseBinding<T>(
          key, 'bloc is ${isClosed ? 'closed' : 'closing'}',
          level: Level.warning);
    }
    final run = RestartableRun.current;
    if (run?.isSuperseded ?? false) {
      // The run was superseded before it got here (a callback it scheduled,
      // an await it was behind): its bindings were cancelled at the
      // supersede, and a new one would outlive the fence unowned.
      return _refuseBinding<T>(key, 'run superseded');
    }
    if (key != null) unbind(key);

    late final StreamBinding<T> binding;
    binding = StreamBinding.create<T>(key, (b) {
      _bindings.remove(b);
      run?.bindings.remove(b);
      if (b.key != null && identical(_keyedBindings[b.key!], b)) {
        _keyedBindings.remove(b.key!);
      }
    });

    // Every callback the binding owner wrote is guarded: its throw is the
    // bloc's error (logged `stream_binding` / `callback_error`), never an
    // uncaught error out of a stream event.
    void guarded(String callbackName, void Function() callback) {
      try {
        callback();
      } catch (error, stackTrace) {
        _logger.record(JuiceTelemetry(
          JuiceTelemetryKind.streamBindingCallbackError,
          bloc: _name,
          key: key,
          callback: callbackName,
          error: error,
          stackTrace: stackTrace,
        ));
        this.onError(error, stackTrace);
      }
    }

    void fail(Object error, StackTrace stackTrace) {
      if (onError != null) {
        guarded('onError', () => onError(error, stackTrace));
      } else {
        _logger.record(JuiceTelemetry(
          JuiceTelemetryKind.streamBindingError,
          bloc: _name,
          key: key,
          error: error,
          stackTrace: stackTrace,
        ));
        this.onError(error, stackTrace);
      }
      if (cancelOnError) _cancelLogged(binding, 'on error');
    }

    // Listen BEFORE registering: a stream whose listen throws leaves no
    // binding behind, and the throw reaches the caller as it would from
    // `Stream.listen` itself.
    final subscription = stream.listen(
      (item) => guarded('onData', () => onData(item)),
      onError: fail,
      onDone: () {
        StreamBinding.finish(binding);
        if (JuiceLoggerConfig.logs(Level.info)) {
          _logger.record(JuiceTelemetry(JuiceTelemetryKind.streamBindingDone,
              bloc: _name, key: key));
        }
        if (onDone != null) guarded('onDone', onDone);
      },
      cancelOnError: false, // handled in [fail], so onError always runs
    );
    StreamBinding.attach(binding, subscription);
    _bindings.add(binding);
    run?.bindings.add(binding);
    if (key != null) _keyedBindings[key] = binding;
    if (JuiceLoggerConfig.logs(Level.info)) {
      _logger.record(JuiceTelemetry(JuiceTelemetryKind.streamBound,
          bloc: _name, key: key));
    }
    return binding;
  }

  /// A binding `bindStream` will not create: logged as `stream_binding` /
  /// `refused` with the [reason], returned inert (already done, never
  /// active).
  StreamBinding<T> _refuseBinding<T>(String? key, String reason,
      {Level level = Level.info}) {
    if (JuiceLoggerConfig.logs(level)) {
      _logger.record(JuiceTelemetry(
        JuiceTelemetryKind.streamBindingRefused,
        level: level,
        bloc: _name,
        key: key,
        reason: reason,
      ));
    }
    return StreamBinding.inert<T>(key);
  }

  /// Cancel the binding registered under [key]. True if there was one.
  bool unbind(String key) {
    final binding = _keyedBindings.remove(key);
    if (binding == null) return false;
    _cancelLogged(binding, 'at unbind');
    return true;
  }

  /// The bindings currently listening (keyed and anonymous).
  int get activeBindingCount => _bindings.length;

  /// A `restartable` run was superseded: cancel the bindings it created —
  /// exactly those, from the run's own list.
  void _cancelBindingsOf(RestartableRun run) {
    for (final b in run.bindings.toList()) {
      _cancelLogged(b as StreamBinding<dynamic>, 'at supersede');
    }
  }

  /// Cancel a binding. A subscription whose cancel throws — synchronously
  /// or through its future — is logged as `stream_binding` /
  /// `cancel_error`: never an uncaught error, never a reason to stop
  /// cancelling the rest. The returned future never fails.
  Future<void> _cancelLogged(StreamBinding<dynamic> b, String where) async {
    try {
      await b.cancel();
    } catch (e, st) {
      _logger.record(JuiceTelemetry(
        JuiceTelemetryKind.streamBindingCancelError,
        bloc: _name,
        key: b.key,
        reason: where,
        error: e,
        stackTrace: st,
      ));
    }
  }

  /// TEST SEAM: put the bloc into [state] without running a use case.
  /// Emits an `UpdatingStatus` carrying an `UpdateEvent` with
  /// [groups], exactly as a use case's `emitUpdate` would, so widgets and
  /// listeners see a normal emission. Throws on a closed or closing bloc.
  /// Production code changes state through a use case — never this.
  @visibleForTesting
  void seedState(TState state, {Set<String>? groups}) {
    if (isClosing) {
      throw StateError('seedState on a closed or closing $runtimeType');
    }
    final event = UpdateEvent(groupsToRebuild: groups);
    _statusEmitter.emitUpdate(event, state, event.groupsToRebuild);
  }

  /// Whether [event]'s `restartable` run has been superseded by a newer
  /// same-type event. False for any other event. Inside the use case,
  /// `BlocUseCase.isSuperseded` needs no event.
  bool isSuperseded(EventBase event) => _dispatcher.isSuperseded(event);

  /// Cancel every binding and await their subscriptions' cancels — the
  /// first step of [close], before the use cases close.
  Future<void> _cancelBindings() async {
    if (_bindings.isEmpty) return;
    // One binding's failing cancel must not abort the close of everything
    // else: each failure is logged, the rest still awaited.
    await Future.wait([
      for (final b in _bindings.toList()) _cancelLogged(b, 'at close'),
    ]);
  }

  // ============================================================
  // Public API
  // ============================================================

  /// The current state of the bloc.
  TState get state => _stateManager.current.state;

  /// The previous state of the bloc.
  TState get oldState => _stateManager.current.oldState;

  /// The current status with metadata.
  @override
  StreamStatus<TState> get currentStatus => _stateManager.current;

  /// Stream of status changes.
  @override
  Stream<StreamStatus<TState>> get stream => _stateManager.stream;

  /// Whether the bloc is closed.
  @override
  bool get isClosed => _stateManager.isClosed;

  /// True once [close] has started — and stays true after it completes
  /// (then [isClosed] is true as well). Monotonic, like `SyncBloc`'s own
  /// flag it now formalizes.
  ///
  /// New events are refused from here on, so nothing is dispatched into a
  /// bloc that is tearing down. Use cases already in flight keep running and
  /// can check this to stop early; their emits after the close completes are
  /// dropped (the close fence).
  bool get isClosing => _closing || isClosed;
  bool _closing = false;

  /// Sends an event to be processed by its registered use case.
  ///
  /// If the bloc is closed, the event is ignored and a warning is logged.
  Future<void> send(EventBase event) {
    // Not `async`: the dispatcher's future is returned through, not awaited
    // here — one microtask hop less per send. The executor keeps the one
    // structural await (it closes the span).
    if (isClosed || _closing) {
      _logger.record(JuiceTelemetry(
        JuiceTelemetryKind.eventIgnored,
        bloc: _name,
        event: typeName(event.runtimeType),
        reason: isClosed ? 'bloc is closed' : 'bloc is closing',
      ));
      return Future<void>.value();
    }
    return _dispatcher.dispatch(event);
  }

  /// Sends a cancellable event and returns it for cancellation control.
  ///
  /// On a closed or closing bloc the event is refused exactly as [send]
  /// refuses it (logged `event_ignored`); the event is still returned.
  T sendCancellable<T extends CancellableEvent>(T event) {
    send(event);
    return event;
  }

  /// Sends an event and waits for processing to complete.
  ///
  /// This method sends the event and returns the first status emitted FOR
  /// THIS EVENT that is not a [WaitingStatus] — an [UpdatingStatus],
  /// [FailureStatus], or [CancelingStatus]. Emissions caused by other events
  /// are ignored.
  ///
  /// [event] - The event to send.
  /// [timeout] - Maximum time to wait for completion (default: 30 seconds).
  ///
  /// Returns the final [StreamStatus] after processing completes.
  ///
  /// Fails loud instead of waiting out [timeout] when the outcome is already
  /// known to be missing, with a [StateError]:
  /// - the bloc is closed or closing (the event would be refused);
  /// - the bloc closes while the wait is pending;
  /// - processing finished without a terminal status for this event — it
  ///   was dropped by a `droppable` builder, no use case handles it, or its
  ///   use case emitted nothing. (Work a use case leaves running after it
  ///   returns cannot be waited for; its emit is not this event's answer.)
  ///
  /// A `restartable` event superseded before it emitted answers with a
  /// [CancelingStatus] for the event (not put on the stream).
  ///
  /// Throws [TimeoutException] if nothing terminal arrives within [timeout].
  ///
  /// Example:
  /// ```dart
  /// final status = await bloc.sendAndWait(FetchDataEvent());
  /// if (status is FailureStatus) {
  ///   print('Failed: ${status.error}');
  /// }
  /// ```
  Future<StreamStatus<TState>> sendAndWait(
    EventBase event, {
    Duration timeout = const Duration(seconds: 30),
  }) {
    if (isClosing) {
      return Future<StreamStatus<TState>>.error(
          StateError('sendAndWait(${event.runtimeType}) on a closed or '
              'closing $runtimeType'),
          StackTrace.current);
    }
    // Observe emissions SYNCHRONOUSLY through the state manager's tap, not a
    // stream subscription: the tap sees the event's result in the same
    // tick it is emitted (a stream listener is a microtask behind, which
    // let a supersede signal win a race the emission had already decided),
    // and it is removed on every exit, so a superseded, failed or timed-out
    // wait leaves nothing listening.
    final done = Completer<StreamStatus<TState>>();
    late final void Function() untap;
    late final Timer timer;
    late final void Function() failOnClose;
    void finish(StreamStatus<TState>? status,
        [Object? error, StackTrace? stackTrace]) {
      if (done.isCompleted) return;
      untap();
      timer.cancel();
      _pendingWaits.remove(failOnClose);
      if (error != null) {
        done.completeError(error, stackTrace);
      } else {
        done.complete(status);
      }
    }

    untap = tapEmissions((s) {
      if (identical(s.event, event) && s is! WaitingStatus<TState>) finish(s);
    });
    timer = Timer(timeout, () {
      finish(
          null, TimeoutException('sendAndWait(${event.runtimeType})', timeout));
    });
    failOnClose = () => finish(
        null,
        StateError(
            '$runtimeType closed while sendAndWait(${event.runtimeType}) was pending'));
    _pendingWaits.add(failOnClose);

    final restartable = _dispatcher.isRestartable(event.runtimeType);
    send(event).then((_) {
      // Processing is over. A restartable run that was superseded answers
      // below; anything else that emitted nothing never will.
      if (done.isCompleted ||
          (restartable && _dispatcher.isSuperseded(event))) {
        return;
      }
      final type = event.runtimeType;
      finish(
          null,
          StateError(!_dispatcher.hasHandler(type)
              ? 'sendAndWait($type): no use case is registered for $type'
              : _dispatcher.wasDropped(event)
                  ? '$type was dropped by its droppable builder (an earlier '
                      '$type was still running)'
                  : '$type finished without a terminal status — its use '
                      'case emitted nothing for it'));
    }, onError: (Object e, StackTrace st) => finish(null, e, st));
    if (restartable) {
      // A superseded restartable run is fenced: it never emits. Answer with
      // a CancelingStatus for THIS event (not put on the stream) — unless
      // the tap already recorded its result, which then wins.
      _dispatcher.whenSuperseded(event).then((_) {
        if (!done.isCompleted) {
          finish(StreamStatus.canceling(state, oldState, event));
        }
      });
    }
    return done.future;
  }

  /// The `sendAndWait`s still pending, each as the closure that fails it; a
  /// close runs them so no wait is left to time out.
  final Set<void Function()> _pendingWaits = {};

  /// Observes every emission SYNCHRONOUSLY (inside the emit, before stream
  /// delivery). Returns the remover. Framework-internal — `sendAndWaitResult`
  /// uses it to know an event's terminal status the moment processing ends.
  @internal
  void Function() tapEmissions(
          void Function(StreamStatus<TState> status) observer) =>
      _stateManager.tap(observer);

  /// Triggers an update with the current state.
  void start() => send(UpdateEvent());

  /// Puts [status] on the stream as is — the raw [Emittable] interface, with
  /// no logging, no group defaults and no event. Production code changes
  /// state through a use case; a test seeds state with [seedState].
  @protected
  @visibleForTesting
  @override
  void emit(StreamStatus<TState> status) {
    _stateManager.emit(status);
  }

  /// Reports an error which triggers [onError].
  @protected
  @mustCallSuper
  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    onError(error, stackTrace ?? StackTrace.current);
  }

  /// Called when an error occurs. Override to customize error handling.
  @protected
  @mustCallSuper
  void onError(Object error, StackTrace stackTrace) {
    _logger.record(JuiceTelemetry(
      JuiceTelemetryKind.blocError,
      bloc: _name,
      state: state,
      error: error,
      stackTrace: stackTrace,
    ));

    try {
      _errorHandler.handleError(
        'Unhandled bloc error',
        error: error,
        stackTrace: stackTrace,
      );
    } catch (e, handlerStackTrace) {
      _logger.record(JuiceTelemetry(
        JuiceTelemetryKind.errorHandlerFailed,
        bloc: _name,
        error: e,
        stackTrace: handlerStackTrace,
      ));
    }
  }

  /// Closes the bloc and releases all resources.
  @mustCallSuper
  @override
  Future<void> close() {
    // Memoized: a second caller (a scope ending while a widget disposes)
    // awaits the same teardown instead of returning before it finishes.
    return _closeFuture ??= _close();
  }

  Future<void>? _closeFuture;

  Future<void> _close() async {
    if (isClosed) return;
    _closing = true;

    _logger.record(JuiceTelemetry(
      JuiceTelemetryKind.blocClosing,
      bloc: _name,
      count: _bindings.length,
    ));

    await _cancelBindings();
    for (final fail in _pendingWaits.toList()) {
      fail();
    }
    await _useCaseRegistry.closeAll();
    await _aviatorManager.closeAll();
    await Future.wait(_eventSubscriptions.map((s) => s.close()));
    _eventSubscriptions.clear();
    _dispatcher.clear();
    await _stateManager.close();
  }

  /// Synchronous cleanup method for Flutter widget compatibility.
  ///
  /// This calls [close] internally. Prefer using [close] directly
  /// when you need to await cleanup completion.
  void dispose() {
    close();
  }

  // ============================================================
  // Initialization
  // ============================================================

  void _initialize(
    List<UseCaseBuilderGenerator> useCases,
    List<AviatorBuilder> aviatorBuilders,
  ) {
    _registerBuiltInUseCases();
    _registerUseCases(useCases);
    _registerAviators(aviatorBuilders);
  }

  void _registerBuiltInUseCases() {
    _registerUseCase(UseCaseBuilder(
      typeOfEvent: UpdateEvent,
      useCaseGenerator: () => UpdateUseCase(),
      concurrency: EventConcurrency.concurrent,
    ));
  }

  final List<EventSubscription> _eventSubscriptions = [];

  void _registerUseCases(List<UseCaseBuilderGenerator> useCases) {
    for (final generator in useCases) {
      final builder = generator();

      // Handle EventSubscription specially
      if (builder is EventSubscription) {
        _registerEventSubscription(builder);
      } else {
        _registerUseCase(builder);
      }

      // Fire initial event if configured
      if (builder.initialEventBuilder != null) {
        final event = builder.initialEventBuilder!();
        if (event.runtimeType == builder.eventType) {
          send(event);
        }
      }
    }
  }

  void _registerUseCase(UseCaseBuilderBase builder) {
    if (builder is UseCaseBuilder) builder.checkRegisteredOn(this);
    if (builder is StatefulUseCaseBuilder &&
        builder.concurrency == EventConcurrency.restartable) {
      // The fence is per RUN and lives in the context wired onto the use
      // case; a shared instance is re-wired by every new run, so the
      // superseded run would emit through the current run's context,
      // unfenced. Refused at registration rather than silently unfenced.
      throw ArgumentError(
          'StatefulUseCaseBuilder for ${builder.eventType} cannot be '
          'restartable: one instance serves every run, so a superseded run '
          'cannot be fenced. Use UseCaseBuilder, or another mode.');
    }
    _useCaseRegistry.register(builder);

    _dispatcher.register<EventBase>(
      (event) => _useCaseExecutor.execute(builder, event),
      eventType: builder.eventType,
      concurrency: builder.concurrency,
    );
  }

  void _registerEventSubscription(EventSubscription subscription) {
    _eventSubscriptions.add(subscription);

    // Only register the use case if no handler exists for this event type
    final eventType = subscription.eventType;
    if (!_useCaseRegistry.hasBuilder(eventType)) {
      _registerUseCase(subscription);
    }

    // Wire up to dispatch transformed events via send()
    subscription.setEventHandler((event) {
      send(event);
    });

    // Initialize the subscription to listen to source bloc
    subscription.initialize();
  }

  void _registerAviators(List<AviatorBuilder> aviatorBuilders) {
    for (final generator in aviatorBuilders) {
      _aviatorManager.register(generator());
    }
  }

  // ============================================================
  // Context Factory
  // ============================================================

  /// The two context closures that capture no event, made once per bloc
  /// instead of once per execution.
  late final void Function(EventBase?) _emitEventTearOff = _emitEvent;
  late final void Function(String?, Map<String, dynamic>?) _navigateTearOff =
      _aviatorManager.navigate;

  UseCaseContext<JuiceBloc<TState>, TState> _createContext(EventBase event) {
    if (_dispatcher.isRestartable(event.runtimeType)) {
      return _fencedContext(event);
    }
    return UseCaseContext(
      bloc: this,
      emitUpdate: (newState, groups, {bool skipIfSame = false}) =>
          _statusEmitter.emitUpdate(event, newState, groups,
              skipIfSame: skipIfSame),
      emitWaiting: (newState, groups) =>
          _statusEmitter.emitWaiting(event, newState, groups),
      emitFailure: (newState, groups,
              {Object? error, StackTrace? errorStackTrace}) =>
          _statusEmitter.emitFailure(event, newState, groups,
              error: error, errorStackTrace: errorStackTrace),
      emitCancel: (newState, groups) =>
          _statusEmitter.emitCancel(event, newState, groups),
      emitEvent: _emitEventTearOff,
      navigate: _navigateTearOff,
    );
  }

  /// Re-emits the current status carrying [event] (no state change), through
  /// the close fence like every other emission.
  void _emitEvent(EventBase? event) {
    if (event != null) _statusEmitter.emitEvent(event);
  }

  /// The context of a `restartable` run: every emission and navigation is
  /// dropped once the run is superseded, each drop logged as
  /// `state_emission_superseded`. Built only for restartable types, so the
  /// other modes pay nothing for the fence.
  UseCaseContext<JuiceBloc<TState>, TState> _fencedContext(EventBase event) {
    // The RUN, not the event, is what gets superseded: the same event
    // instance sent twice is two runs, and only the first is fenced. The
    // context is created inside the run's zone (the executor runs there),
    // so this is that run; a field read per emit, no lookup.
    final run = RestartableRun.current;
    if (run == null) {
      throw StateError(
          'A restartable use case for ${event.runtimeType} is executing '
          'outside its run zone — the dispatcher did not wrap it. This is a '
          'framework bug; it must never be silently unfenced.');
    }
    bool fenced(String status) {
      if (!run.isSuperseded) return false;
      if (JuiceLoggerConfig.logs(Level.info)) {
        _logger.record(JuiceTelemetry(
          JuiceTelemetryKind.emissionSuperseded,
          bloc: _name,
          event: typeName(event.runtimeType),
          status: status,
        ));
      }
      return true;
    }

    return UseCaseContext(
      bloc: this,
      emitUpdate: (newState, groups, {bool skipIfSame = false}) {
        if (fenced('update')) return;
        _statusEmitter.emitUpdate(event, newState, groups,
            skipIfSame: skipIfSame);
      },
      emitWaiting: (newState, groups) {
        if (fenced('waiting')) return;
        _statusEmitter.emitWaiting(event, newState, groups);
      },
      emitFailure: (newState, groups,
          {Object? error, StackTrace? errorStackTrace}) {
        if (fenced('failure')) return;
        _statusEmitter.emitFailure(event, newState, groups,
            error: error, errorStackTrace: errorStackTrace);
      },
      emitCancel: (newState, groups) {
        if (fenced('cancel')) return;
        _statusEmitter.emitCancel(event, newState, groups);
      },
      emitEvent: (EventBase? e) {
        if (e == null || fenced('event')) return;
        _emitEvent(e);
      },
      navigate: (aviator, args) {
        // Every emit closure also calls navigate (with null when no aviator
        // was named): nothing to drop, nothing to log.
        if (aviator == null) return;
        if (fenced('navigate')) return;
        _aviatorManager.navigate(aviator, args);
      },
    );
  }

  // ============================================================
  // Error Handling
  // ============================================================

  void _handleUnhandledEvent(EventBase event) {
    final message = 'No use case registered for ${event.runtimeType}';
    _logger.record(JuiceTelemetry(
      JuiceTelemetryKind.unhandledEvent,
      bloc: _name,
      event: typeName(event.runtimeType),
      error: StateError(message),
      stackTrace: StackTrace.current,
    ));
    _errorHandler.handleError(message);
  }

  /// The executor already logged the `use_case_error` span-closer; here the
  /// error reaches [onError] (the `bloc_error` hook and the error handler).
  void _handleUseCaseError(Object error, StackTrace stack, EventBase event) =>
      onError(error, stack);
}
