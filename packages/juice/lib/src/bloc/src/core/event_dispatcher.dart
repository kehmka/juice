import 'dart:async';

import 'package:logger/web.dart';

import '../cancellable_event.dart';
import '../juice_logger.dart';
import 'event_concurrency.dart';
import 'restartable_run.dart';

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
///   concurrency: EventConcurrency.concurrent,
/// );
///
/// await dispatcher.dispatch(IncrementEvent(amount: 5));
/// ```
class EventDispatcher<Event extends Object> {
  /// Creates an EventDispatcher.
  ///
  /// [onUnhandledEvent] is called when an event has no registered handler.
  /// Without it, dispatching an unhandled event returns a future that fails
  /// with a [StateError].
  EventDispatcher({
    void Function(Event event)? onUnhandledEvent,
    void Function(RestartableRun run)? onSuperseded,
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
  final void Function(RestartableRun run)? _onSuperseded;

  /// Event types registered `restartable`, and their in-flight run.
  final _restartableTypes = <Type>{};
  final _current = <Type, RestartableRun>{};

  /// Events a `droppable` wrapper dropped (identity keyed), so a waiter
  /// can fail fast instead of waiting for an emission that never comes.
  final _dropped = Expando<bool>('juice.dropped');

  /// Whether [event] was dropped by its `droppable` wrapper.
  bool wasDropped(Event event) => _dropped[event] ?? false;

  /// The run executing each restartable event (identity keyed; an event
  /// that was never dispatched restartable has none).
  final _runOf = Expando<RestartableRun>('juice.run');

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
  ///   concurrency: EventConcurrency.sequential,
  /// );
  /// ```
  /// [concurrency] is how same-type events are processed relative to one
  /// another; every registration declares it.
  void register<E extends Event>(
    EventHandler<E> handler, {
    required Type eventType,
    required EventConcurrency concurrency,
  }) {
    if (_handlers.containsKey(eventType)) {
      throw StateError('Handler already registered for $eventType');
    }
    Future<void> raw(Event event) => handler(event as E);
    // A dispatch made from INSIDE a restartable run (a nested send, a
    // queued sequential run, a stream listener the run created) would
    // inherit that run's zone — its bindings would be tagged as the outer
    // run's, its `isSuperseded` would be the outer run's, its span flagged.
    // Shadow the token for the nested handler; costs a zone fork only when
    // nested, nothing on the plain path.
    Future<void> outsideRun(Event event) => RestartableRun.current == null
        ? raw(event)
        : runZoned(() => raw(event),
            zoneValues: {RestartableRun.zoneKey: null});
    _handlers[eventType] = switch (concurrency) {
      EventConcurrency.concurrent => outsideRun,
      EventConcurrency.sequential => (event) =>
          _sequential(eventType, outsideRun, event),
      EventConcurrency.droppable => (event) =>
          _droppable(eventType, outsideRun, event),
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
  bool isSuperseded(Event event) => _runOf[event]?.isSuperseded ?? false;

  /// Completes if [event]'s run is superseded; never completes otherwise
  /// (race it against the result you are waiting for).
  Future<void> whenSuperseded(Event event) =>
      _runOf[event]?.whenSuperseded ?? Completer<void>().future;

  /// `restartable`: supersede the in-flight run of [type] (fence it, cancel
  /// its CancellableEvent, hand it to [_onSuperseded]) and run [event] at
  /// once inside a zone that carries its [RestartableRun].
  Future<void> _restartable(
      Type type, EventHandler<Event> handler, Event event) {
    if (_disposed) return Future<void>.value();
    final run = RestartableRun(event);
    _runOf[event] = run;
    final previous = _current[type];
    _current[type] = run;
    // A run whose use case already RETURNED has nothing left to fence and
    // its bindings belong to the bloc; the dispatcher's whenComplete that
    // clears _current lags that return by a few microtasks.
    if (previous != null && !previous.isComplete) {
      _supersede(type, previous, event);
    }
    return runZoned(() => handler(event),
        zoneValues: {RestartableRun.zoneKey: run}).whenComplete(() {
      if (identical(_current[type], run)) _current.remove(type);
    });
  }

  void _supersede(Type type, RestartableRun previous, Object newEvent) {
    previous.supersede();
    final event = previous.event;
    // Nothing in here may throw into the sender's frame or leave the new
    // run un-started: a user-overridden cancel(), the logger, the bloc's
    // binding cancel are all guarded. Loud, then on with the new run.
    try {
      // The same instance re-sent: cancelling it would cancel the NEW run
      // too (cancel() is permanent). The fence is per run, so skip it.
      if (event is CancellableEvent && !identical(event, newEvent)) {
        event.cancel();
      }
      if (JuiceLoggerConfig.logs(Level.info)) {
        _log.log('Use case superseded', context: {
          'type': 'use_case_superseded',
          'event': type.toString(),
          'cancellable': event is CancellableEvent,
        });
      }
      _onSuperseded?.call(previous);
    } catch (e, st) {
      _log.logError('Error while superseding a run', e, st, context: {
        'type': 'use_case_superseded',
        'action': 'error',
        'event': type.toString(),
      });
    }
  }

  /// Queue [event] behind any in-flight/queued same-type runs; one at a time.
  Future<void> _sequential(
      Type type, EventHandler<Event> handler, Event event) {
    final run = (_tails[type] ?? Future<void>.value()).then((_) {
      if (_disposed) {
        return null; // queued after close → skip (no emit-after-close)
      }
      // The executor routes a use case's errors through onError; anything
      // that escapes it (a throwing generator) is logged here, not dropped.
      return handler(event).catchError((Object e, StackTrace st) {
        _log.logError('Sequential run failed outside the executor', e, st,
            context: {'type': 'use_case_error', 'event': type.toString()});
      });
    });
    _tails[type] = run;
    return run; // dispatch()/send() await full processing
  }

  /// Drop [event] if a same-type run is already in flight.
  Future<void> _droppable(Type type, EventHandler<Event> handler, Event event) {
    if (_running[type] == true) {
      _dropped[event] = true;
      return Future<void>.value();
    }
    if (_disposed) return Future<void>.value();
    _running[type] = true;
    return handler(event).whenComplete(() => _running[type] = false);
  }

  /// Checks if a handler is registered for the given event type.
  bool hasHandler(Type eventType) => _handlers.containsKey(eventType);

  /// Dispatches an event to its registered handler.
  ///
  /// Returns a Future that completes when the handler finishes. With no
  /// handler registered it calls [onUnhandledEvent] if provided, otherwise
  /// the returned future fails with a [StateError].
  Future<void> dispatch(Event event) {
    // Not `async`: the handler's future is returned through (one hop less).
    // The no-handler error is still delivered ASYNCHRONOUSLY, as a failed
    // future, so an un-awaited send never throws into its caller's frame —
    // the contract `async` gave for free, kept on purpose.
    final handler = _handlers[event.runtimeType];
    if (handler == null) {
      if (_onUnhandledEvent != null) {
        _log.log(
          'No handler registered for ${event.runtimeType}, using fallback handler',
          level: Level.warning,
        );
        try {
          _onUnhandledEvent(event);
        } catch (e, st) {
          return Future<void>.error(e, st);
        }
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
