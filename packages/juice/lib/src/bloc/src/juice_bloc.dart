// ignore_for_file: deprecated_member_use_from_same_package

import 'dart:async';
import 'package:flutter/foundation.dart';

import 'bloc_state.dart';
import 'bloc_event.dart';
import 'stream_status.dart';
import 'juice_logger.dart';
import 'bloc_use_case.dart';
import 'bloc_error_handler.dart';
import 'cancellable_event.dart';
import 'use_case_builders/use_case_builder.dart';
import 'aviators/aviator.dart';
import 'core/state_manager.dart';
import 'core/event_dispatcher.dart';
import 'core/use_case_registry.dart';
import 'core/use_case_executor.dart';
import 'core/status_emitter.dart';
import 'core/aviator_manager.dart';
import 'bloc.dart' show Emittable, ErrorSink, StateStreamableSource;

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
  JuiceLogger get logger => _logger;

  final BlocErrorHandler _errorHandler;

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

  /// Sends an event to be processed by its registered use case.
  Future<void> send(EventBase event) => _dispatcher.dispatch(event);

  /// Sends a cancellable event and returns it for cancellation control.
  T sendCancellable<T extends CancellableEvent>(T event) {
    send(event);
    return event;
  }

  /// Sends an event and waits for processing to complete.
  ///
  /// This method sends the event and returns when the status changes from
  /// [WaitingStatus] to either [UpdatingStatus], [FailureStatus], or
  /// [CancelingStatus].
  ///
  /// [event] - The event to send.
  /// [timeout] - Maximum time to wait for completion (default: 30 seconds).
  ///
  /// Returns the final [StreamStatus] after processing completes.
  ///
  /// Throws [TimeoutException] if the operation doesn't complete within
  /// the timeout duration.
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
  }) async {
    await send(event);
    return stream
        .firstWhere((s) => s is! WaitingStatus<TState>)
        .timeout(timeout);
  }

  /// Triggers an update with the current state.
  void start() => send(UpdateEvent(newState: state));

  /// Emits a new status directly.
  ///
  /// Prefer using use cases for state changes. This is primarily
  /// for internal use and testing.
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
    _logger.logError('Bloc error', error, stackTrace, context: {
      'type': 'bloc_error',
      'bloc': runtimeType.toString(),
      'state': state.toString(),
    });

    try {
      _errorHandler.handleError(
        'Unhandled bloc error',
        error: error,
        stackTrace: stackTrace,
      );
    } catch (e, handlerStackTrace) {
      _logger.logError('Error in custom errorHandler', e, handlerStackTrace,
          context: {
            'type': 'error_handler_error',
            'bloc': runtimeType.toString()
          });
    }
  }

  /// Closes the bloc and releases all resources.
  @mustCallSuper
  @override
  Future<void> close() async {
    if (isClosed) return;

    _logger.log('Closing bloc', context: {
      'type': 'bloc_lifecycle',
      'action': 'close',
      'bloc': runtimeType.toString(),
    });

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
    ));
    _registerUseCase(UseCaseBuilder(
      typeOfEvent: UpdateEvent<TState>,
      useCaseGenerator: () => UpdateUseCase(),
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
    _useCaseRegistry.register(builder);

    _dispatcher.register<EventBase>(
      (event) => _useCaseExecutor.execute(builder, event),
      eventType: builder.eventType,
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

  UseCaseContext<JuiceBloc<TState>, TState> _createContext(EventBase event) {
    return UseCaseContext(
      bloc: this,
      getState: () => state,
      getOldState: () => oldState,
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
      emitEvent: (EventBase? e) {
        if (e != null) {
          _stateManager.emit(currentStatus.copyWith(event: e));
        }
      },
      navigate: _aviatorManager.navigate,
    );
  }

  // ============================================================
  // Error Handling
  // ============================================================

  void _handleUnhandledEvent(EventBase event) {
    final message = 'No use case registered for ${event.runtimeType}';
    _logger
        .logError(message, StateError(message), StackTrace.current, context: {
      'type': 'unhandled_event',
      'bloc': runtimeType.toString(),
      'event': event.runtimeType.toString(),
    });
    _errorHandler.handleError(message);
  }

  void _handleUseCaseError(Object error, StackTrace stack, EventBase event) {
    _logger.logError('Use case error', error, stack, context: {
      'type': 'use_case_error',
      'bloc': runtimeType.toString(),
      'event': event.runtimeType.toString(),
      'state': state.toString(),
    });

    onError(error, stack);
  }
}
