import 'dart:async';

import 'package:logger/web.dart';

import '../cancellable_event.dart';
import '../juice_logger.dart';
import 'event_concurrency.dart';
import 'execution_run.dart';

/// Signature for async event handlers.
typedef EventHandler<E> = Future<void> Function(E event);

/// Routes events to their registered handlers.
///
/// Each event type can have exactly one handler registered.
/// When an event is dispatched, the dispatcher looks up the handler
/// by the event's runtime type and invokes it.
///
/// Example:
/// ```dart
/// final dispatcher = EventDispatcher<MyEvent>();
///
/// dispatcher.register<IncrementEvent>(
///   (event) async => print('Increment by ${event.amount}'),
///   eventType: IncrementEvent,
/// );
///
/// await dispatcher.dispatch(IncrementEvent(amount: 5));
/// ```
class EventDispatcher<Event> {
  /// Creates an EventDispatcher.
  ///
  /// [onUnhandledEvent] is called when an event has no registered handler.
  /// If not provided, dispatching an unhandled event throws a [StateError].
  EventDispatcher({
    void Function(Event event)? onUnhandledEvent,
    void Function(ExecutionRun run)? onSuperseded,
    JuiceLogger? logger,
  })  : _onUnhandledEvent = onUnhandledEvent,
        _onSuperseded = onSuperseded,
        _logger = logger;

  /// The owning bloc's logger; the global one when constructed bare.
  final JuiceLogger? _logger;
  JuiceLogger get _log => _logger ?? JuiceLoggerConfig.logger;

  final _handlers = <Type, EventHandler<Event>>{};
  final void Function(Event event)? _onUnhandledEvent;

  /// Called when a `restartable` run is superseded, after its event is
  /// cancelled and before the new run starts — the bloc cancels the run's
  /// stream bindings here.
  final void Function(ExecutionRun run)? _onSuperseded;

  /// Event types registered `restartable`, and their in-flight run.
  final _restartableTypes = <Type>{};
  final _current = <Type, ExecutionRun>{};

  /// The run executing each restartable event (identity keyed; an event
  /// that was never dispatched restartable has none).
  final _runOf = Expando<ExecutionRun>('juice.run');

  /// Per-type FIFO tails for [EventConcurrency.sequential].
  final _tails = <Type, Future<void>>{};

  /// Per-type "running" flags for [EventConcurrency.droppable].
  final _running = <Type, bool>{};

  /// Set by [clear] (on bloc close) so queued sequential runs don't emit after
  /// the state manager has closed.
  bool _disposed = false;

  /// Registers a handler for a specific event type.
  ///
  /// [handler] is the function to call when events of type [E] are dispatched.
  /// [eventType] specifies the runtime type to match against. This is required
  /// because Dart's generic type [E] is erased at runtime.
  ///
  /// Throws [StateError] if a handler is already registered for the event type.
  ///
  /// Example:
  /// ```dart
  /// dispatcher.register<MyEvent>(
  ///   (event) async => handleEvent(event),
  ///   eventType: MyEvent,
  /// );
  /// ```
  /// [concurrency] controls how same-type events are processed relative to one
  /// another (default [EventConcurrency.concurrent] — today's behavior).
  void register<E extends Event>(
    EventHandler<E> handler, {
    required Type eventType,
    EventConcurrency concurrency = EventConcurrency.concurrent,
  }) {
    if (_handlers.containsKey(eventType)) {
      throw StateError('Handler already registered for $eventType');
    }
    Future<void> raw(Event event) => handler(event as E);
    _handlers[eventType] = switch (concurrency) {
      EventConcurrency.concurrent => raw,
      EventConcurrency.sequential => (event) =>
          _sequential(eventType, raw, event),
      EventConcurrency.droppable => (event) =>
          _droppable(eventType, raw, event),
      EventConcurrency.restartable => (event) =>
          _restartable(eventType, raw, event),
    };
    if (concurrency == EventConcurrency.restartable) {
      _restartableTypes.add(eventType);
    }
  }

  /// Whether [eventType] is registered `restartable` — the bloc builds the
  /// emission fence into a run's context only then.
  bool isRestartable(Type eventType) => _restartableTypes.contains(eventType);

  /// Whether [event]'s run has been superseded by a newer same-type event.
  /// False for an event that is not restartable or not in flight.
  bool isSuperseded(Event event) =>
      event == null ? false : (_runOf[event as Object]?.isSuperseded ?? false);

  /// Completes if [event]'s run is superseded; never completes otherwise
  /// (race it against the result you are waiting for).
  Future<void> whenSuperseded(Event event) {
    final run = event == null ? null : _runOf[event as Object];
    return run?.whenSuperseded ?? Completer<void>().future;
  }

  /// `restartable`: supersede the in-flight run of [type] (fence it, cancel
  /// its CancellableEvent, hand it to [_onSuperseded]) and run [event] at
  /// once inside a zone that carries its [ExecutionRun].
  Future<void> _restartable(
      Type type, EventHandler<Event> handler, Event event) {
    if (_disposed) return Future<void>.value();
    final run = ExecutionRun(event as Object);
    _runOf[event] = run;
    final previous = _current[type];
    _current[type] = run;
    if (previous != null) _supersede(type, previous);
    return runZoned(() => handler(event),
        zoneValues: {ExecutionRun.zoneKey: run}).whenComplete(() {
      if (identical(_current[type], run)) _current.remove(type);
    });
  }

  void _supersede(Type type, ExecutionRun previous) {
    previous.supersede();
    final event = previous.event;
    if (event is CancellableEvent) event.cancel();
    if (JuiceLoggerConfig.logs(Level.info)) {
      _log.log('Use case superseded', context: {
        'type': 'use_case_superseded',
        'event': type.toString(),
        'cancellable': event is CancellableEvent,
      });
    }
    _onSuperseded?.call(previous);
  }

  /// Queue [event] behind any in-flight/queued same-type runs; one at a time.
  Future<void> _sequential(
      Type type, EventHandler<Event> handler, Event event) {
    final run = (_tails[type] ?? Future<void>.value()).then((_) {
      if (_disposed) {
        return null; // queued after close → skip (no emit-after-close)
      }
      // The executor already routes use-case errors via its own onError.
      return handler(event).catchError((_) {});
    });
    _tails[type] = run;
    return run; // dispatch()/send() await full processing
  }

  /// Drop [event] if a same-type run is already in flight.
  Future<void> _droppable(Type type, EventHandler<Event> handler, Event event) {
    if (_running[type] == true) return Future<void>.value();
    if (_disposed) return Future<void>.value();
    _running[type] = true;
    return handler(event).whenComplete(() => _running[type] = false);
  }

  /// Checks if a handler is registered for the given event type.
  bool hasHandler(Type eventType) => _handlers.containsKey(eventType);

  /// The number of registered handlers.
  int get handlerCount => _handlers.length;

  /// Dispatches an event to its registered handler.
  ///
  /// Returns a Future that completes when the handler finishes.
  ///
  /// If no handler is registered:
  /// - Calls [onUnhandledEvent] if provided
  /// - Otherwise throws [StateError]
  Future<void> dispatch(Event event) {
    // Not `async`: the handler's future is returned through (one hop less).
    // The no-handler error is still delivered ASYNCHRONOUSLY, as a failed
    // future, so an un-awaited send never throws into its caller's frame —
    // the contract `async` gave for free, kept on purpose (2.0.0).
    final handler = _handlers[event.runtimeType];
    if (handler == null) {
      if (_onUnhandledEvent != null) {
        _log.log(
          'No handler registered for ${event.runtimeType}, using fallback handler',
          level: Level.warning,
        );
        _onUnhandledEvent(event);
        return Future<void>.value();
      }
      return Future<void>.error(
        StateError('No handler registered for ${event.runtimeType}'),
        StackTrace.current,
      );
    }
    return handler(event);
  }

  /// Removes all registered handlers and concurrency state.
  void clear() {
    _disposed = true;
    _handlers.clear();
    _tails.clear();
    _running.clear();
    _restartableTypes.clear();
    _current.clear();
  }
}
