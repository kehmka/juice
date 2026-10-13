import 'package:flutter_test/flutter_test.dart' hide EventDispatcher;
import 'package:juice/juice.dart';
import 'package:juice/src/bloc/src/core/event_dispatcher.dart';
import 'package:juice/src/bloc/src/core/use_case_registry.dart';

class _S extends BlocState {
  const _S();
}

class _A extends EventBase {}

class _B extends EventBase {}

class _C extends EventBase {}

class _AUseCase extends BlocUseCase<_DupBloc, _A> {
  @override
  Future<void> execute(_A event) async {}
}

class _DupBloc extends JuiceBloc<_S> {
  _DupBloc()
      : super(const _S(), [
          () => UseCaseBuilder(
              typeOfEvent: _A,
              useCaseGenerator: () => _AUseCase(),
              concurrency: EventConcurrency.concurrent),
          () => UseCaseBuilder(
              typeOfEvent: _A,
              useCaseGenerator: () => _AUseCase(),
              concurrency: EventConcurrency.concurrent),
        ]);
}

class _ClosingBuilder extends UseCaseBuilderBase {
  _ClosingBuilder(this.eventType);

  @override
  final Type eventType;

  int closes = 0;

  @override
  UseCaseGenerator get generator => () => NoOpUseCase();

  @override
  UseCaseEventBuilder? get initialEventBuilder => null;

  @override
  EventConcurrency get concurrency => EventConcurrency.concurrent;

  @override
  Future<void> close() async => closes++;
}

class _Log implements JuiceLogger {
  final errors = <Map<String, dynamic>>[];
  @override
  void log(String m,
      {Level level = Level.info, Map<String, dynamic>? context}) {}
  @override
  void logError(String m, Object e, StackTrace s,
          {Map<String, dynamic>? context}) =>
      errors.add({'message': m, 'error': e, ...?context});
}

void main() {
  group('UseCaseRegistry', () {
    test('register/lookup/enumerate builders by event type', () {
      final registry = UseCaseRegistry();
      final a = _ClosingBuilder(_A);
      final b = _ClosingBuilder(_B);
      expect(registry.builders, isEmpty);
      registry.register(a);
      registry.register(b);

      expect(registry.builders, hasLength(2));
      expect(registry.hasBuilder(_A), isTrue);
      expect(registry.hasBuilder(_C), isFalse);
      expect(registry.getBuilder(_A), same(a));
      expect(registry.getBuilder(_C), isNull);
      expect(registry.builders, unorderedEquals([a, b]));
      expect(registry.eventTypes, unorderedEquals([_A, _B]));
    });

    test('duplicate registration for the same event type throws', () {
      final registry = UseCaseRegistry()..register(_ClosingBuilder(_A));
      expect(
        () => registry.register(_ClosingBuilder(_A)),
        throwsA(isA<StateError>().having(
            (e) => e.message, 'message', contains('already registered'))),
      );
    });

    test('closeAll closes every builder and empties the registry', () async {
      final registry = UseCaseRegistry();
      final a = _ClosingBuilder(_A);
      final b = _ClosingBuilder(_B);
      registry
        ..register(a)
        ..register(b);
      await registry.closeAll();
      expect(a.closes, 1);
      expect(b.closes, 1);
      expect(registry.builders, isEmpty);
      expect(registry.hasBuilder(_A), isFalse);
    });

    test('a JuiceBloc with two builders for one event type fails fast', () {
      expect(() => _DupBloc(), throwsStateError);
    });
  });

  group('EventDispatcher', () {
    test('routes by exact runtime type and reports handler count', () async {
      final d = EventDispatcher<EventBase>();
      final seen = <String>[];
      d.register<_A>((e) async => seen.add('a'),
          eventType: _A, concurrency: EventConcurrency.concurrent);
      d.register<_B>((e) async => seen.add('b'),
          eventType: _B, concurrency: EventConcurrency.concurrent);
      expect(d.hasHandler(_A), isTrue);
      expect(d.hasHandler(_C), isFalse);

      await d.dispatch(_B());
      await d.dispatch(_A());
      expect(seen, ['b', 'a']);
    });

    test('registering a second handler for a type throws', () {
      final d = EventDispatcher<EventBase>();
      d.register<_A>((e) async {},
          eventType: _A, concurrency: EventConcurrency.concurrent);
      expect(
        () => d.register<_A>((e) async {},
            eventType: _A, concurrency: EventConcurrency.concurrent),
        throwsA(isA<StateError>().having(
            (e) => e.message, 'message', contains('already registered'))),
      );
    });

    test('unhandled event throws without a fallback', () async {
      final d = EventDispatcher<EventBase>();
      await expectLater(
        d.dispatch(_C()),
        throwsA(isA<StateError>()
            .having((e) => e.message, 'message', contains('_C'))),
      );
    });

    test('unhandled event goes to the fallback when provided', () async {
      final unhandled = <EventBase>[];
      final d = EventDispatcher<EventBase>(onUnhandledEvent: unhandled.add);
      final e = _C();
      await d.dispatch(e);
      expect(unhandled.single, same(e));
    });

    test('clear() removes handlers so later dispatch is unhandled', () async {
      final d = EventDispatcher<EventBase>();
      d.register<_A>((e) async {},
          eventType: _A, concurrency: EventConcurrency.concurrent);
      d.clear();
      expect(d.hasHandler(_A), isFalse);
      await expectLater(d.dispatch(_A()), throwsStateError);
    });

    test('a failed sequential handler is logged and the queue continues',
        () async {
      final log = _Log();
      final d = EventDispatcher<EventBase>(logger: log);
      var calls = 0;
      d.register<_A>((e) async {
        calls++;
        if (calls == 1) throw StateError('first fails');
      }, eventType: _A, concurrency: EventConcurrency.sequential);
      await d.dispatch(_A());
      await d.dispatch(_A());
      expect(calls, 2);
      expect(log.errors.single['type'], 'use_case_error');
      expect(log.errors.single['event'], '_A');
    });
  });
}
