import 'package:flutter/material.dart';

import '../bloc.dart';
import "bloc_support.dart";

part 'bloc_base.dart';
part 'emitter.dart';

abstract class BlocEventSink<Event extends Object?> implements ErrorSink {
  /// Adds an [event] to the sink.
  ///
  /// Must not be called on a closed sink.
  void send(Event event);
}

/// An event handler is responsible for reacting to an incoming [Event]
/// and can emit zero or more states via the [Emitter].
typedef EventHandler<Event, State> = FutureOr<void> Function(
  Event event,
  Emitter<State> emit,
);

typedef UseCaseHandler<Event, State> = Future<void> Function(
    Event, Emitter<State>);

/// Used to change how events are processed.
/// By default events are processed concurrently.
typedef EventTransformer<Event> = Stream<Event> Function(
  Stream<Event> events,
  EventMapper<Event> mapper,
);

class _Handler<Event, State> {
  const _Handler(
      {required this.isType, required this.handler, required this.type});
  final bool Function(dynamic value) isType;
  final UseCaseHandler<Event, State> handler;
  final Type type;
}

abstract class Bloc<Event, State> extends BlocBase<State>
    implements BlocEventSink<Event> {
  /// {@macro bloc}
  Bloc(super.initialState, {this.errorHandler = const BlocErrorHandler()});

  final _eventController = StreamController<Event>.broadcast();
  final _subscriptions = <StreamSubscription<dynamic>>[];
  final _handlers = <_Handler>[];
  final _emitters = <_Emitter>[];
  final BlocErrorHandler errorHandler;

  @protected
  void handleEventError(String message,
      {Object? error, StackTrace? stackTrace}) {
    errorHandler.handleError(message, error: error, stackTrace: stackTrace);
  }

  @visibleForTesting
  @override
  void emit(State state) => super.emit(state);

  /// Creates an emitter and handles the event processing lifecycle
  Future<void> _processEvent<E extends Event>(
    E event,
    UseCaseHandler<E, State> handler,
  ) async {
    void onEmit(State state) {
      if (isClosed) return;
      emit(state);
    }

    final emitter = _Emitter<State>(onEmit);
    final controller = StreamController<E>.broadcast(
      sync: true,
      onCancel: emitter.cancel,
    );

    void onDone() {
      emitter.complete();
      _emitters.remove(emitter);
      if (!controller.isClosed) controller.close();
    }

    try {
      _emitters.add(emitter);
      await handler(event, emitter);
    } catch (error, stackTrace) {
      handleEventError('Error processing event ${event.runtimeType}',
          error: error, stackTrace: stackTrace);
      rethrow;
    } finally {
      onDone();
    }
  }

  @override
  Future<void> send(Event event) async {
    final hasHandler = _handlers.any((h) => h.type == event.runtimeType);
    if (!hasHandler) {
      final exception = NoEventHandlerException(runtimeType, event.runtimeType);
      handleEventError(exception.message,
          error: exception, stackTrace: StackTrace.current);
      return;
    }

    final handler = _handlers
        .where((h) => h.type == event.runtimeType)
        .cast<_Handler<Event, State>>()
        .first
        .handler;

    await _processEvent(event, handler);
  }

  T sendCancellable<T extends CancellableEvent>(T event) {
    send(event as Event);
    return event;
  }

  @protected
  void register<E extends Event>(
    UseCaseHandler<E, State> handler,
    Type eventType, {
    EventTransformer<E>? transformer,
  }) {
    _handlers.add(_Handler<E, State>(
        isType: (dynamic e) => e.runtimeType == eventType,
        handler: handler,
        type: eventType));

    final transformer0 = transformer ?? defaultEventTransformer;
    final subscription = transformer0(
      _eventController.stream
          .where((event) => event.runtimeType == eventType)
          .cast<E>(),
      (dynamic event) {
        _processEvent(event as E, handler);
        return Stream.empty(); // Since we handle the event directly
      },
    ).listen(null);
    _subscriptions.add(subscription);
  }

  @mustCallSuper
  @override
  Future<void> close() async {
    await _eventController.close();
    for (final emitter in _emitters) {
      emitter.cancel();
    }
    await Future.wait<void>(_emitters.map((e) => e.future));
    await Future.wait<void>(_subscriptions.map((s) => s.cancel()));
    _handlers.clear();
    _emitters.clear();
    _subscriptions.clear();
    return super.close();
  }
}
