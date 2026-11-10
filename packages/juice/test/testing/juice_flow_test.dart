import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';
import 'package:juice/src/bloc/src/core/activity_probe.dart';
import 'package:juice/testing.dart';

import '../support/capture_logger.dart';

/// juiceFlowTest: several blocs and the reactions between them. The flow
/// knows when every bloc in the process is idle (a send in flight — queued
/// ones included — or a reaction hop pending is not idle), so a test sends,
/// lets the whole chain finish, and asserts on exactly what each bloc
/// emitted. It fails on anything the test did not account for.

class _S extends BlocState {
  const _S(this.n);
  final int n;
  @override
  bool operator ==(Object o) => o is _S && o.n == n;
  @override
  int get hashCode => n.hashCode;
  @override
  String toString() => '_S($n)';
}

class _Set extends EventBase {
  _Set(this.n);
  final int n;
}

/// Sets `n` after 5 ms of real time; `sequential`, so a second one queues.
class _Slow extends EventBase {
  _Slow(this.n);
  final int n;
}

/// Waits for [gate], then sets `n` to 77.
class _Park extends EventBase {
  _Park(this.gate);
  final Future<void> gate;
}

/// Returns at once, leaving work behind that emits when [gate] completes.
class _Leak extends EventBase {
  _Leak(this.gate);
  final Future<void> gate;
}

/// Returns at once, leaving a zero timer behind that sends `_Set(n)` — or,
/// [relays] times first, another `_Later`.
class _Later extends EventBase {
  _Later(this.n, {this.relays = 0});
  final int n;
  final int relays;
}

/// Logs a line and an error through the use case's own helpers, then fails
/// its status — a failure the use case handled.
class _Chatty extends EventBase {}

class _Boom extends EventBase {}

class _Bump extends EventBase {}

class _Unknown extends EventBase {}

class _SetUC extends BlocUseCase<_Counter, _Set> {
  @override
  Future<void> execute(_Set e) async => emitUpdate(newState: _S(e.n));
}

class _SlowUC extends BlocUseCase<_Counter, _Slow> {
  @override
  Future<void> execute(_Slow e) async {
    await Future<void>.delayed(const Duration(milliseconds: 5));
    emitUpdate(newState: _S(e.n));
  }
}

class _ParkUC extends BlocUseCase<_Counter, _Park> {
  @override
  Future<void> execute(_Park e) async {
    await e.gate;
    emitUpdate(newState: const _S(77));
  }
}

class _LeakUC extends BlocUseCase<_Counter, _Leak> {
  @override
  Future<void> execute(_Leak e) async {
    // Fire-and-forget: outlives the run, and nothing can see it.
    e.gate.then((_) => emitUpdate(newState: const _S(99)));
  }
}

class _LaterUC extends BlocUseCase<_Counter, _Later> {
  @override
  Future<void> execute(_Later e) async {
    Timer.run(() => bloc
        .send(e.relays > 0 ? _Later(e.n, relays: e.relays - 1) : _Set(e.n)));
  }
}

class _ChattyUC extends BlocUseCase<_Counter, _Chatty> {
  @override
  Future<void> execute(_Chatty e) async {
    log('a line from the use case');
    final error = StateError('handled');
    logError(error, StackTrace.current);
    emitFailure(error: error);
  }
}

class _BoomUC extends BlocUseCase<_Counter, _Boom> {
  @override
  Future<void> execute(_Boom e) async => throw StateError('boom');
}

class _BumpUC extends BlocUseCase<_Counter, _Bump> {
  @override
  Future<void> execute(_Bump e) async {
    // A ring whose hop bound does not hold would spin forever and starve
    // the event loop: fail fast instead.
    if (bloc.state.n >= 40) {
      throw StateError('runaway ring: the hop bound did not hold');
    }
    emitUpdate(newState: _S(bloc.state.n + 1));
  }
}

class _Counter extends JuiceBloc<_S> {
  _Counter({
    JuiceLogger? logger,
    BlocErrorHandler errorHandler = const BlocErrorHandler(),
  }) : super(
          const _S(0),
          [
            () => UseCaseBuilder(
                typeOfEvent: _Set,
                useCaseGenerator: () => _SetUC(),
                concurrency: EventConcurrency.concurrent),
            () => UseCaseBuilder(
                typeOfEvent: _Slow,
                useCaseGenerator: () => _SlowUC(),
                concurrency: EventConcurrency.sequential),
            () => UseCaseBuilder(
                typeOfEvent: _Park,
                useCaseGenerator: () => _ParkUC(),
                concurrency: EventConcurrency.concurrent),
            () => UseCaseBuilder(
                typeOfEvent: _Leak,
                useCaseGenerator: () => _LeakUC(),
                concurrency: EventConcurrency.concurrent),
            () => UseCaseBuilder(
                typeOfEvent: _Later,
                useCaseGenerator: () => _LaterUC(),
                concurrency: EventConcurrency.concurrent),
            () => UseCaseBuilder(
                typeOfEvent: _Chatty,
                useCaseGenerator: () => _ChattyUC(),
                concurrency: EventConcurrency.concurrent),
            () => UseCaseBuilder(
                typeOfEvent: _Boom,
                useCaseGenerator: () => _BoomUC(),
                concurrency: EventConcurrency.concurrent),
            () => UseCaseBuilder(
                typeOfEvent: _Bump,
                useCaseGenerator: () => _BumpUC(),
                concurrency: EventConcurrency.concurrent),
          ],
          const [],
          logger,
          errorHandler,
        );
}

class _A extends _Counter {}

/// Follows [_A], resolved by type: slowly sets its own `n` to A's.
class _B extends _Counter {
  _B() {
    react(Reaction<_A, _S>.changes(
      (s) => s.n,
      send: (s) => _Slow(s.n),
      atAttach: AtAttach.skip,
    ));
  }
}

/// Follows [_B] the same way: the third link of the chain.
class _C extends _Counter {
  _C() {
    react(Reaction<_B, _S>.changes(
      (s) => s.n,
      send: (s) => _Slow(s.n),
      atAttach: AtAttach.skip,
    ));
  }
}

/// Completes [closed] once its close is over — work left behind by a
/// [_Leak] then emits into a closed bloc.
class _ClosesThenReleases extends _Counter {
  final closed = Completer<void>();

  @override
  Future<void> close() => super.close().then((_) {
        if (!closed.isCompleted) closed.complete();
      });
}

class _CloseThrows extends _Counter {
  @override
  Future<void> close() async {
    await super.close();
    throw StateError('close broke');
  }
}

class _RegisteredCloseThrows extends _CloseThrows {}

/// [a] follows [source]'s `n` with a plain, synchronous [_Set].
ReactionBinding _follow(_Counter a, _Counter source,
        {AtAttach atAttach = AtAttach.skip}) =>
    a.react(Reaction<_Counter, _S>.changes(
      (s) => s.n,
      source: source,
      send: (s) => _Set(s.n),
      atAttach: atAttach,
    ));

Matcher _updated(int n) => isUpdatingStatus(state: _S(n));

Matcher _fails(Object message) =>
    throwsA(isA<TestFailure>().having((f) => f.message, 'message', message));

void main() {
  late JuiceLogger savedLogger;
  late CaptureLogger configured;

  setUp(() {
    savedLogger = JuiceLoggerConfig.logger;
    configured = CaptureLogger();
    JuiceLoggerConfig.configureLogger(configured);
  });

  tearDown(() async {
    JuiceLoggerConfig.configureLogger(savedLogger);
    await BlocScope.reset();
  });

  group('idle', () {
    juiceFlowTest('one send settles a whole chain of reactions', (flow) async {
      final a = flow.register<_A>(() => _A());
      final b = flow.register<_B>(() => _B());
      final c = flow.register<_C>(() => _C());

      await flow.send(a, _Set(3));

      // B and C each took 5 ms of real time, one after the other.
      flow.expect(a, [_updated(3)]);
      flow.expect(b, [_updated(3)]);
      flow.expect(c, [_updated(3)]);
    });

    juiceFlowTest(
        'an event waiting in a sequential queue is in flight — it has no '
        'span yet, which is why telemetry cannot be the signal', (flow) async {
      final a = flow.add(_Counter());

      a.send(_Slow(1));
      a.send(_Slow(2));
      a.send(_Slow(3));
      await flow.settle();

      flow.expect(a, [_updated(1), _updated(2), _updated(3)]);
    });

    juiceFlowTest('settle with nothing in flight completes', (flow) async {
      final a = flow.add(_Counter());
      await flow.settle();
      flow.expect(a, isEmpty);
    });

    juiceFlowTest(
        'a bloc the flow was not handed: its sends are waited for, its '
        'emissions are not recorded, and the flow does not close it',
        (flow) async {
      final quiet = _Counter();
      addTearDown(() {
        expect(quiet.isClosed, isFalse);
        return quiet.close();
      });

      quiet.send(_Slow(5));
      await flow.settle();

      expect(quiet.state.n, 5);
    });

    juiceFlowTest('a catch-up hop at attach is waited for', (flow) async {
      final a = flow.add(_Counter());
      await flow.send(a, _Set(4));
      flow.expect(a, [_updated(4)]);

      final follower = flow.add(_Counter());
      _follow(follower, a, atAttach: AtAttach.catchUp);
      expect(follower.state.n, 0, reason: 'a hop is sent a microtask later');
      await flow.settle();

      flow.expect(follower, [_updated(4)]);
    });

    juiceFlowTest(
        'a settle that does not go idle in time fails, naming what is '
        'still in flight', (flow) async {
      final a = flow.add(_Counter());
      final gate = Completer<void>();
      a.send(_Park(gate.future));

      await expectLater(
        flow.settle(timeout: const Duration(milliseconds: 30)),
        _fails(allOf(
          contains('not idle after 0:00:00.030000'),
          contains('send _Park to _Counter'),
        )),
      );

      gate.complete();
      await flow.settle();
      flow.expect(a, [_updated(77)]);
    });

    juiceFlowTest(
        'a send made from a stream listener, a microtask after the '
        'emission it heard, is waited for — idle must hold for a whole '
        'turn', (flow) async {
      final a = flow.add(_Counter());
      final b = flow.add(_Counter());
      // Not a reaction: nothing tells the flow this is coming.
      final sub = a.stream.listen((status) => b.send(_Slow(status.state.n)));
      addTearDown(sub.cancel);

      await flow.send(a, _Set(6));

      flow.expect(a, [_updated(6)]);
      flow.expect(b, [_updated(6)]);
    });

    juiceFlowTest(
        'a send a use case left on a zero timer is waited for: the blocs '
        'were idle, and something began within the turn', (flow) async {
      final a = flow.add(_Counter());

      await flow.send(a, _Later(8));

      flow.expect(a, [_updated(8)]);
    });

    juiceFlowTest(
        'a relay of zero timers is followed turn by turn: a turn in which '
        'anything began is not an idle one', (flow) async {
      final a = flow.add(_Counter());

      await flow.send(a, _Later(9, relays: 3));

      flow.expect(a, [_updated(9)]);
    });
  });

  group('expect', () {
    juiceFlowTest('consumes: the next expect sees only what came after',
        (flow) async {
      final a = flow.add(_Counter());

      await flow.send(a, _Set(1));
      flow.expect(a, [_updated(1)]);

      await flow.send(a, _Set(2));
      await flow.send(a, _Set(3));
      flow.expect(a, [_updated(2), _updated(3)]);

      flow.expect(a, isEmpty);
    });

    juiceFlowTest('a mismatch fails, naming the bloc and what it emitted',
        (flow) async {
      final a = flow.add(_Counter());
      await flow.send(a, _Set(1));

      expect(
        () => flow.expect(a, [isWaitingStatus()]),
        _fails(allOf(contains('_Counter emitted'), contains('_S(1)'))),
      );
      // The failed expect consumed what it looked at.
      flow.expect(a, isEmpty);
    });

    juiceFlowTest('one matcher over the whole list', (flow) async {
      final a = flow.add(_Counter());
      await flow.send(a, _Set(1));
      await flow.send(a, _Set(2));
      flow.expect(a, hasLength(2));
    });

    juiceFlowTest('a bloc the flow was not handed cannot be asserted on',
        (flow) async {
      final stranger = _Counter();
      addTearDown(stranger.close);
      expect(
        () => flow.expect(stranger, isEmpty),
        throwsA(isA<ArgumentError>().having(
            (e) => e.message, 'message', contains('_Counter is not watched'))),
      );
    });

    juiceFlowTest('order is per bloc: each bloc has its own list',
        (flow) async {
      final a = flow.add(_Counter());
      final b = flow.add(_Counter());
      _follow(b, a);

      await flow.send(a, _Set(1));
      await flow.send(a, _Set(2));

      // b first, then a: neither list depends on the other.
      flow.expect(b, [_updated(1), _updated(2)]);
      flow.expect(a, [_updated(1), _updated(2)]);
    });
  });

  group('the end of the flow fails the test on', () {
    test('an emission no expect consumed', () async {
      await expectLater(
        runJuiceFlow((flow) async {
          final a = flow.add(_Counter());
          final b = flow.add(_Counter());
          _follow(b, a);
          await flow.send(a, _Set(1));
          flow.expect(a, [_updated(1)]);
          // b reacted, and nobody looked.
        }),
        _fails(allOf(
          contains('_Counter emitted 1 status(es) no flow.expect consumed'),
          contains('_S(1)'),
        )),
      );
    });

    test('a send still in flight', () async {
      final gate = Completer<void>();
      await expectLater(
        runJuiceFlow((flow) async {
          final a = flow.add(_Counter());
          a.send(_Park(gate.future));
        }),
        _fails(allOf(
          contains('still in flight when the test ended'),
          contains('send _Park to _Counter'),
        )),
      );
      gate.complete();
    });

    test('a refused chain of reactions — it cannot be claimed', () async {
      await expectLater(
        runJuiceFlow((flow) async {
          final a = flow.add(_Counter());
          final b = flow.add(_Counter());
          // A ring: each bumps itself when the other's n changes.
          a.react(Reaction<_Counter, _S>.changes((s) => s.n,
              source: b, send: (_) => _Bump(), atAttach: AtAttach.skip));
          b.react(Reaction<_Counter, _S>.changes((s) => s.n,
              source: a, send: (_) => _Bump(), atAttach: AtAttach.skip));

          await flow.send(a, _Bump());

          // The ring ran to the bound and stopped: 1 sent + 8 hops.
          expect(a.state.n + b.state.n, 1 + Reaction.maxHops);
          flow.expect(a, anything);
          flow.expect(b, anything);
          flow.expectErrors(isEmpty);
        }),
        _fails(allOf(
          contains('a chain of reactions was refused'),
          contains('past Reaction.maxHops'),
        )),
      );
    });

    test('an error nobody claimed', () async {
      await expectLater(
        runJuiceFlow((flow) async {
          final a = flow.add(_Counter());
          await flow.send(a, _Boom());
        }),
        _fails(allOf(
          contains('unexpected error(s)'),
          contains('boom'),
          contains('flow.expectErrors'),
        )),
      );
    });

    test('an emission dropped while the blocs were closing', () async {
      await expectLater(
        runJuiceFlow((flow) async {
          final a = flow.add(_ClosesThenReleases());
          await flow.send(a, _Leak(a.closed.future));
        }),
        _fails(contains('1 emission(s) dropped while the blocs were closing')),
      );
    });

    test('a close that threw — a watched instance, and a registered one',
        () async {
      await expectLater(
        runJuiceFlow((flow) async {
          flow.add(_CloseThrows());
          BlocScope.register<_RegisteredCloseThrows>(
              () => _RegisteredCloseThrows(),
              lifecycle: BlocLifecycle.permanent);
          BlocScope.get<_RegisteredCloseThrows>();
          flow.expectErrors(anything);
        }),
        _fails(allOf(
          contains('closing _CloseThrows threw'),
          contains('resetting BlocScope threw'),
          contains('close broke'),
        )),
      );
      expect(BlocScope.isRegistered<_RegisteredCloseThrows>(), isFalse,
          reason: 'a reset resets, whatever a close threw');
    });

    test('everything at once: one failure lists every problem', () async {
      final gate = Completer<void>();
      await expectLater(
        runJuiceFlow((flow) async {
          final a = flow.add(_Counter());
          await flow.send(a, _Set(1));
          await flow.send(a, _Boom());
          a.send(_Park(gate.future));
        }),
        _fails(allOf(
          contains('- still in flight'),
          contains('- _Counter emitted 1 status(es)'),
          contains('- unexpected error(s)'),
        )),
      );
      gate.complete();
    });
  });

  group('errors', () {
    juiceFlowTest('a use case that threw is claimed with expectErrors',
        (flow) async {
      final a = flow.add(_Counter());
      await flow.send(a, _Boom());
      flow.expectErrors([
        isA<StateError>().having((e) => e.message, 'message', 'boom'),
      ]);
      flow.expectErrors(isEmpty);
    });

    juiceFlowTest("a reaction's own failure is an error to claim",
        (flow) async {
      final a = flow.add(_Counter());
      final b = flow.add(_Counter());
      b.react(Reaction<_Counter, _S>.changes(
        (s) => s.n,
        source: a,
        send: (_) => throw StateError('send broke'),
        atAttach: AtAttach.skip,
      ));

      await flow.send(a, _Set(1));

      flow.expect(a, [_updated(1)]);
      flow.expectErrors([
        isA<StateError>().having((e) => e.message, 'message', 'send broke'),
      ]);
    });

    juiceFlowTest(
        'an event with no use case does not fail the send: it is an error '
        'to claim', (flow) async {
      final a = flow.add(_Counter());
      await flow.send(a, _Unknown());
      flow.expectErrors([
        isA<StateError>().having(
            (e) => e.message, 'message', 'No use case registered for _Unknown'),
      ]);
    });

    juiceFlowTest('flow.send rethrows what the send itself failed with',
        (flow) async {
      final a = flow.add(_Counter(
          errorHandler: BlocErrorHandler(
              onError: (message, {error, stackTrace}) =>
                  throw StateError('the handler threw'))));

      await expectLater(
        flow.send(a, _Unknown()),
        throwsA(isA<StateError>()
            .having((e) => e.message, 'message', 'the handler threw')),
      );
      flow.expectErrors(hasLength(1));
    });

    juiceFlowTest(
        'a failure the use case handled itself is an emission to assert, '
        'not an error — and its log lines reach the logger that was '
        'configured', (flow) async {
      final a = flow.add(_Counter());

      await flow.send(a, _Chatty());

      flow.expect(a, [isFailureStatus(error: isA<StateError>())]);
      flow.expectErrors(isEmpty);
      final messages = [for (final e in configured.entries) e['message']];
      expect(messages, contains('[_ChattyUC] a line from the use case'));
      expect(configured.errors, hasLength(1));
      // Framework entries are forwarded too.
      expect(messages, contains('State emitted'));
    });
  });

  group('blocs', () {
    test(
        'register: permanent in BlocScope, built at once, the instance a '
        'type-resolved reaction finds; closed and unregistered at the end',
        () async {
      late _A a;
      late _B b;
      await runJuiceFlow((flow) async {
        a = flow.register<_A>(() => _A());
        expect(BlocScope.diagnostics<_A>()!.lifecycle, BlocLifecycle.permanent);
        expect(BlocScope.diagnostics<_A>()!.isActive, isTrue);
        expect(identical(BlocScope.get<_A>(), a), isTrue);

        b = flow.register<_B>(() => _B());
        await flow.send(a, _Set(9));
        flow.expect(a, [_updated(9)]);
        flow.expect(b, [_updated(9)]);
      });
      expect(a.isClosed, isTrue);
      expect(b.isClosed, isTrue);
      expect(BlocScope.isRegistered<_A>(), isFalse);
      expect(BlocScope.isRegistered<_B>(), isFalse);
    });

    test('add: returns the instance, and the flow closes it at the end',
        () async {
      late _Counter a;
      await runJuiceFlow((flow) async {
        final built = _Counter();
        a = flow.add(built);
        expect(identical(a, built), isTrue);
      });
      expect(a.isClosed, isTrue);
    });

    juiceFlowTest('a bloc the test closes itself is fine at the end',
        (flow) async {
      final a = flow.add(_Counter());
      final b = flow.add(_Counter());
      final binding = _follow(b, a);

      await a.close();
      expect(binding.isActive, isFalse, reason: 'the source closed');
    });

    juiceFlowTest('add refuses a bloc it already watches', (flow) async {
      final a = flow.add(_Counter());
      expect(
        () => flow.add(a),
        throwsA(isA<ArgumentError>()
            .having((e) => e.message, 'message', contains('already watched'))),
      );
    });

    juiceFlowTest('add refuses a closed bloc', (flow) async {
      final a = _Counter();
      await a.close();
      expect(
        () => flow.add(a),
        throwsA(isA<ArgumentError>().having(
            (e) => e.message, 'message', contains('closed or closing'))),
      );
    });

    juiceFlowTest(
        'add refuses a bloc with its own logger: its errors would go '
        'unseen', (flow) async {
      final a = _Counter(logger: CaptureLogger());
      addTearDown(a.close);
      expect(
        () => flow.add(a),
        throwsA(isA<ArgumentError>().having((e) => e.message, 'message',
            contains('does not report to the flow'))),
      );
    });

    test('add refuses a bloc built before the flow started', () async {
      final early = _Counter();
      addTearDown(early.close);
      await runJuiceFlow((flow) async {
        expect(
          () => flow.add(early),
          throwsA(isA<ArgumentError>().having((e) => e.message, 'message',
              contains('built before the flow started'))),
        );
      });
    });
  });

  group('starting and ending', () {
    test('will not start while BlocScope holds a registration', () async {
      BlocScope.register<_A>(() => _A());
      var ran = false;
      await expectLater(
        runJuiceFlow((flow) async => ran = true),
        throwsA(isA<StateError>().having((e) => e.message, 'message',
            contains('BlocScope already holds a registration'))),
      );
      expect(ran, isFalse);
      expect(BlocScope.isRegistered<_A>(), isTrue,
          reason: 'a flow that did not start destroyed nothing');
      expect(JuiceActivityProbe.current, isNull);
    });

    juiceFlowTest('one flow at a time', (flow) async {
      await expectLater(
        runJuiceFlow((inner) async {}),
        throwsA(isA<StateError>().having((e) => e.message, 'message',
            contains('a flow is already running'))),
      );
      // The refused flow took nothing away from this one.
      final a = flow.add(_Counter());
      await flow.send(a, _Set(1));
      flow.expect(a, [_updated(1)]);
    });

    test('the logger and the probe are handed back', () async {
      final before = JuiceLoggerConfig.logger;
      expect(JuiceActivityProbe.current, isNull);

      await runJuiceFlow((flow) async {
        expect(identical(JuiceLoggerConfig.logger, before), isFalse);
        expect(JuiceActivityProbe.current, isNotNull);
      });

      expect(identical(JuiceLoggerConfig.logger, before), isTrue);
      expect(JuiceActivityProbe.current, isNull);
    });

    test(
        "the body's own failure is the one reported, with everything "
        'closed and handed back', () async {
      final before = JuiceLoggerConfig.logger;
      late _Counter a;
      await expectLater(
        runJuiceFlow((flow) async {
          a = flow.add(_Counter());
          flow.add(_CloseThrows());
          await flow.send(a, _Set(1)); // never asserted
          throw StateError('mine');
        }),
        throwsA(isA<StateError>().having((e) => e.message, 'message', 'mine')),
      );
      expect(a.isClosed, isTrue);
      expect(identical(JuiceLoggerConfig.logger, before), isTrue);
      expect(JuiceActivityProbe.current, isNull);
    });

    test('a flow is over when its test ends', () async {
      late JuiceFlow leaked;
      late _Counter a;
      await runJuiceFlow((flow) async {
        leaked = flow;
        a = flow.add(_Counter());
      });
      final over = throwsA(isA<StateError>()
          .having((e) => e.message, 'message', contains('this flow is over')));
      expect(() => leaked.add(_Counter()), over);
      expect(() => leaked.register<_A>(() => _A()), over);
      expect(() => leaked.send(a, _Set(1)), over);
      expect(() => leaked.settle(), over);
      expect(() => leaked.expect(a, isEmpty), over);
      expect(() => leaked.expectErrors(isEmpty), over);
    });

    test('outside a flow nothing is counted: send returns as it always did',
        () async {
      final a = _Counter();
      addTearDown(a.close);
      expect(JuiceActivityProbe.current, isNull);
      await a.send(_Set(2));
      expect(a.state.n, 2);
    });

    testWidgets('inside testWidgets, through tester.runAsync', (tester) async {
      await tester.runAsync(() => runJuiceFlow((flow) async {
            final a = flow.register<_A>(() => _A());
            final b = flow.register<_B>(() => _B());
            await flow.send(a, _Set(8));
            flow.expect(a, [_updated(8)]);
            flow.expect(b, [_updated(8)]);
          }));
    });
  });

  group('reactions, through a flow', () {
    juiceFlowTest('becomes: fires when the predicate turns true, once',
        (flow) async {
      final a = flow.add(_Counter());
      final b = flow.add(_Counter());
      b.react(Reaction<_Counter, _S>.becomes(
        (s) => s.n >= 3,
        source: a,
        send: (s) => _Set(s.n * 100),
        atAttach: AtAttach.skip,
      ));

      await flow.send(a, _Set(1));
      flow.expect(b, isEmpty);

      await flow.send(a, _Set(3));
      flow.expect(b, [_updated(300)]);

      await flow.send(a, _Set(4));
      flow.expect(b, isEmpty); // it was already true

      await flow.send(a, _Set(0));
      await flow.send(a, _Set(5));
      flow.expect(b, [_updated(500)]);

      flow.expect(a, hasLength(5));
    });

    juiceFlowTest('edge: any edge over the old and the new state',
        (flow) async {
      final a = flow.add(_Counter());
      final b = flow.add(_Counter());
      b.react(Reaction<_Counter, _S>.edge(
        (old, now) => now.n < old.n,
        source: a,
        send: (s) => _Set(-1),
      ));

      await flow.send(a, _Set(5));
      await flow.send(a, _Set(7));
      flow.expect(b, isEmpty);

      await flow.send(a, _Set(2));
      flow.expect(b, [_updated(-1)]);
      flow.expect(a, hasLength(3));
    });

    juiceFlowTest('a cancelled reaction sends nothing more', (flow) async {
      final a = flow.add(_Counter());
      final b = flow.add(_Counter());
      final binding = _follow(b, a);

      await flow.send(a, _Set(1));
      flow.expect(b, [_updated(1)]);

      binding.cancel();
      await flow.send(a, _Set(2));
      flow.expect(b, isEmpty);
      flow.expect(a, hasLength(2));
    });
  });
}
