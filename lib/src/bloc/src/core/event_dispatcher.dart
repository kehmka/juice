import 'dart:async';

import 'package:logger/logger.dart';

import '../juice_logger.dart';

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
  void register<E extends Event>(
    EventHandler<E> handler, {
    required Type eventType,
  }) {
    if (_handlers.containsKey(eventType)) {
      throw StateError('Handler already registered for $eventType');
    }
    _handlers[eventType] = (event) => handler(event as E);
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

  /// Removes all registered handlers.
  void clear() {
    _handlers.clear();
  }
}
