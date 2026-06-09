import 'dart:async';

import 'package:logger/logger.dart';

import '../juice_logger.dart';
import 'event_concurrency.dart';

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
  EventDispatcher({void Function(Event event)? onUnhandledEvent})
      : _onUnhandledEvent = onUnhandledEvent;

  final _handlers = <Type, EventHandler<Event>>{};
  final void Function(Event event)? _onUnhandledEvent;

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
      EventConcurrency.sequential => (event) => _sequential(eventType, raw, event),
      EventConcurrency.droppable => (event) => _droppable(eventType, raw, event),
    };
  }

  /// Queue [event] behind any in-flight/queued same-type runs; one at a time.
  Future<void> _sequential(Type type, EventHandler<Event> handler, Event event) {
    final run = (_tails[type] ?? Future<void>.value()).then((_) async {
      if (_disposed) return; // queued after close → skip (no emit-after-close)
      try {
        await handler(event);
      } catch (_) {
        // The executor already routes use-case errors via its own onError.
      }
    });
    _tails[type] = run;
    return run; // dispatch()/send() await full processing
  }

  /// Drop [event] if a same-type run is already in flight.
  Future<void> _droppable(Type type, EventHandler<Event> handler, Event event) async {
    if (_running[type] == true) return;
    _running[type] = true;
    try {
      if (!_disposed) await handler(event);
    } finally {
      _running[type] = false;
    }
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
  Future<void> dispatch(Event event) async {
    final handler = _handlers[event.runtimeType];
    if (handler == null) {
      if (_onUnhandledEvent != null) {
        JuiceLoggerConfig.logger.log(
          'No handler registered for ${event.runtimeType}, using fallback handler',
          level: Level.warning,
        );
        _onUnhandledEvent(event);
        return;
      }
      throw StateError('No handler registered for ${event.runtimeType}');
    }
    await handler(event);
  }

  /// Removes all registered handlers and concurrency state.
  void clear() {
    _disposed = true;
    _handlers.clear();
    _tails.clear();
    _running.clear();
  }
}
