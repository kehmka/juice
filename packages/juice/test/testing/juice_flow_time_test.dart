import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';
import 'package:juice/src/bloc/src/core/activity_probe.dart';
import 'package:juice/testing.dart';

import '../support/capture_logger.dart';

/// Time in a juiceFlowTest. A `sendAfter` still pending is not idle, so
/// `flow.send` and `flow.settle` wait for it; `flow.elapse` lets a stated
/// amount of time pass without waiting for idle. With `virtualTime: true`
/// the same test runs on a virtual clock that jumps to the next timer
/// whenever everything is parked — and a test waiting on the real world
/// fails at once instead of hanging.

class _S extends BlocState {
  const _S({this.results = '', this.ticks = 0});
  final String results;
  final int ticks;
  @override
  bool operator ==(Object o) =>
      o is _S && o.results == results && o.ticks == ticks;
  @override
  int get hashCode => Object.hash(results, ticks);
  @override
  String toString() => '_S($results, $ticks)';
}

class _Search extends EventBase {
  _Search(this.text);
  final String text;
}

/// Re-arms itself every second, for ever.
class _Poll extends EventBase {}

class _Tick extends EventBase {}

/// Its use case waits on [world] — something no virtual timer completes.
class _Fetch extends EventBase {
  _Fetch(this.world);
  final Future<void> world;
}

/// Its use case cancels six stream subscriptions, one after the other.
class _Unsubscribe extends EventBase {}

/// Follows the source's results after a further 200 ms.
class _Mirror extends EventBase {
  _Mirror(this.text);
  final String text;
}

class _SearchUC extends BlocUseCase<_Shelf, _Search> {
  @override
  Future<void> execute(_Search e) async {
    // The search itself takes 50 ms.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    emitUpdate(newState: _S(results: 'results for ${e.text}'));
  }
}

class _PollUC extends BlocUseCase<_Shelf, _Poll> {
  @override
  Future<void> execute(_Poll e) async {
    emitUpdate(newState: _S(ticks: bloc.state.ticks + 1));
    bloc.sendAfter(_Poll(), const Duration(seconds: 1), key: 'poll');
  }
}

class _TickUC extends BlocUseCase<_Shelf, _Tick> {
  @override
  Future<void> execute(_Tick e) async =>
      emitUpdate(newState: _S(ticks: bloc.state.ticks + 1));
}

class _FetchUC extends BlocUseCase<_Shelf, _Fetch> {
  @override
  Future<void> execute(_Fetch e) async {
    await e.world;
    emitUpdate(newState: const _S(results: 'fetched'));
  }
}

class _UnsubscribeUC extends BlocUseCase<_Shelf, _Unsubscribe> {
  @override
  Future<void> execute(_Unsubscribe e) async {
    for (var i = 0; i < 6; i++) {
      final subscription = StreamController<int>().stream.listen((_) {});
      // Completes on the REAL microtask queue: the future a plain cancel
      // returns belongs to the root zone, virtual clock or not.
      await subscription.cancel();
    }
    emitUpdate(newState: const _S(results: 'unsubscribed'));
  }
}

class _MirrorUC extends BlocUseCase<_Shelf, _Mirror> {
  @override
  Future<void> execute(_Mirror e) async =>
      emitUpdate(newState: _S(results: e.text));
}

const _defaultDebounce = Duration(milliseconds: 300);

class _Shelf extends JuiceBloc<_S> {
  _Shelf({Duration debounce = _defaultDebounce})
      : _debounce = debounce,
        super(
          const _S(),
          [
            () => UseCaseBuilder(
                typeOfEvent: _Search,
                useCaseGenerator: () => _SearchUC(),
                concurrency: EventConcurrency.restartable),
            () => UseCaseBuilder(
                typeOfEvent: _Poll,
                useCaseGenerator: () => _PollUC(),
                concurrency: EventConcurrency.concurrent),
            () => UseCaseBuilder(
                typeOfEvent: _Tick,
                useCaseGenerator: () => _TickUC(),
                concurrency: EventConcurrency.concurrent),
            () => UseCaseBuilder(
                typeOfEvent: _Fetch,
                useCaseGenerator: () => _FetchUC(),
                concurrency: EventConcurrency.concurrent),
            () => UseCaseBuilder(
                typeOfEvent: _Mirror,
                useCaseGenerator: () => _MirrorUC(),
                concurrency: EventConcurrency.concurrent),
            () => UseCaseBuilder(
                typeOfEvent: _Unsubscribe,
                useCaseGenerator: () => _UnsubscribeUC(),
                concurrency: EventConcurrency.concurrent),
            () => UseCaseBuilder(
                typeOfEvent: _Relay,
                useCaseGenerator: () => _RelayUC(),
                concurrency: EventConcurrency.concurrent),
          ],
        );

  final Duration _debounce;

  /// A keystroke: the search waits out the debounce; a later keystroke
  /// replaces it.
  void typed(String text) => sendAfter(_Search(text), _debounce, key: 'search');
}

/// Ticks once a second off a periodic stream, for as long as it lives.
class _Ticker extends _Shelf {
  _Ticker() {
    bindStream<int>(Stream<int>.periodic(const Duration(seconds: 1), (i) => i),
        (_) => send(_Tick()));
  }
}

/// Mirrors [source]'s results 200 ms after they change.
class _Follower extends _Shelf {
  _Follower(_Shelf source) {
    react(Reaction<_Shelf, _S>.changes(
      (s) => s.results,
      source: source,
      send: (s) => _Relay(s.results),
      atAttach: AtAttach.skip,
    ));
  }
}

class _Relay extends EventBase {
  _Relay(this.text);
  final String text;
}

class _RelayUC extends BlocUseCase<_Shelf, _Relay> {
  @override
  Future<void> execute(_Relay e) async {
    bloc.sendAfter(_Mirror(e.text), const Duration(milliseconds: 200));
  }
}

class _CloseHangs extends _Shelf {
  @override
  Future<void> close() async {
    await super.close();
    await Completer<void>().future;
  }
}

Matcher _results(String text) =>
    isUpdatingStatus(state: _S(results: 'results for $text'));

Matcher _fails(Object message) =>
    throwsA(isA<TestFailure>().having((f) => f.message, 'message', message));

Duration _msec(int n) => Duration(milliseconds: n);

/// Real elapsed time must stay far below the virtual time a test covers.
void _expectInstant(Stopwatch real) =>
    expect(real.elapsed, lessThan(const Duration(seconds: 2)));

void main() {
  late JuiceLogger savedLogger;

  setUp(() {
    savedLogger = JuiceLoggerConfig.logger;
    JuiceLoggerConfig.configureLogger(CaptureLogger());
  });

  tearDown(() async {
    JuiceLoggerConfig.configureLogger(savedLogger);
    JuiceActivityProbe.current = null;
    await BlocScope.reset();
  });

  group('the same test on either clock', () {
    for (final virtual in [false, true]) {
      final clock = virtual ? 'virtual' : 'real';

      juiceFlowTest(
          '$clock: a pending sendAfter is not idle — settle waits the '
          'debounce out, and the search after it', (flow) async {
        final shelf = flow.add(_Shelf(debounce: _msec(30)));

        shelf.typed('juice');
        flow.expect(shelf, isEmpty);
        await flow.settle();

        flow.expect(shelf, [_results('juice')]);
      }, virtualTime: virtual);

      juiceFlowTest(
          '$clock: elapse does not wait for idle — a second keystroke in '
          'the middle of the debounce replaces the search', (flow) async {
        final shelf = flow.add(_Shelf(debounce: _msec(60)));

        shelf.typed('j');
        await flow.elapse(_msec(20));
        flow.expect(shelf, isEmpty);
        shelf.typed('ju');
        await flow.settle();

        flow.expect(shelf, [_results('ju')]);
      }, virtualTime: virtual);

      juiceFlowTest(
          '$clock: a reaction, a delay and another bloc settle as one '
          'chain', (flow) async {
        final shelf = flow.add(_Shelf(debounce: _msec(30)));
        final follower = flow.add(_Follower(shelf));

        shelf.typed('x');
        await flow.settle();

        flow.expect(shelf, [_results('x')]);
        flow.expect(follower,
            [isUpdatingStatus(state: const _S(results: 'results for x'))]);
      }, virtualTime: virtual);

      test('$clock: a delayed send still pending at the end fails the test',
          () async {
        await expectLater(
          runJuiceFlow((flow) async {
            final shelf = flow.add(_Shelf(debounce: _msec(10000)));
            shelf.typed('late');
          }, virtualTime: virtual),
          _fails(allOf(
            contains('still in flight when the test ended'),
            contains('delayed send _Search to _Shelf (after 0:00:10.000000)'),
          )),
        );
      });
    }

    test('real: elapse really waits, and settle really waits a debounce out',
        () async {
      final real = Stopwatch()..start();
      await runJuiceFlow((flow) async {
        final shelf = flow.add(_Shelf(debounce: _msec(60)));
        await flow.elapse(_msec(40));
        expect(real.elapsed, greaterThanOrEqualTo(_msec(40)));
        shelf.typed('slow');
        await flow.settle();
        flow.expect(shelf, [_results('slow')]);
      });
      expect(real.elapsed, greaterThanOrEqualTo(_msec(150)));
    });
  });

  group('virtual time', () {
    test('ten minutes of debounce take no time', () async {
      final real = Stopwatch()..start();
      await runJuiceFlow((flow) async {
        final shelf = flow.add(_Shelf(debounce: const Duration(minutes: 10)));
        shelf.typed('patient');
        await flow.settle(timeout: const Duration(minutes: 11));
        flow.expect(shelf, [_results('patient')]);
      }, virtualTime: true);
      _expectInstant(real);
    });

    juiceFlowTest(
        'settle stops the clock at the moment the blocs go idle, not later',
        (flow) async {
      final shelf = flow.add(_Shelf());
      final fired = <int>[];
      Timer(_msec(349), () => fired.add(349));
      Timer(_msec(350), () => fired.add(350));
      final after = Timer(_msec(351), () => fired.add(351));

      shelf.typed('exact'); // 300 ms debounce + 50 ms search
      await flow.settle();

      flow.expect(shelf, [_results('exact')]);
      expect(fired, [349, 350]);
      // A timer still pending when the flow ends fails it: this one has
      // done its job by NOT firing.
      after.cancel();
    }, virtualTime: true);

    juiceFlowTest('elapse moves the clock by exactly what it was given',
        (flow) async {
      final fired = <int>[];
      Timer(_msec(99), () => fired.add(99));
      Timer(_msec(100), () => fired.add(100));
      Timer(_msec(101), () => fired.add(101));

      await flow.elapse(_msec(100));
      expect(fired, [99, 100]);

      await flow.elapse(Duration.zero);
      expect(fired, [99, 100]);

      await flow.elapse(_msec(1));
      expect(fired, [99, 100, 101]);
    }, virtualTime: true);

    juiceFlowTest(
        "the test's own waits move the clock: a Future.delayed, a waitFor",
        (flow) async {
      final real = Stopwatch()..start();
      final shelf = flow.add(_Shelf());

      await Future<void>.delayed(const Duration(hours: 2));

      shelf.typed('awaited');
      final state = await shelf.waitFor((s) => s.results.isNotEmpty,
          timeout: const Duration(seconds: 2));
      expect(state.results, 'results for awaited');
      flow.expect(shelf, [_results('awaited')]);
      _expectInstant(real);
    }, virtualTime: true);

    juiceFlowTest(
        'a periodic timer is not work: the blocs go idle beside it, and '
        'elapse lets it tick', (flow) async {
      final ticker = flow.add(_Ticker());
      await flow.settle();
      flow.expect(ticker, isEmpty);

      await flow.elapse(const Duration(milliseconds: 3500));
      await flow.settle();

      flow.expect(ticker, hasLength(3));
      expect(ticker.state.ticks, 3);
    }, virtualTime: true);

    juiceFlowTest(
        'a use case awaiting stream cancels — futures of the real microtask '
        'queue — runs to its end before the clock moves', (flow) async {
      final shelf = flow.add(_Shelf());
      final fired = <String>[];
      final probe =
          Timer(const Duration(milliseconds: 1), () => fired.add('1 ms'));

      await flow.send(shelf, _Unsubscribe());

      flow.expect(
          shelf, [isUpdatingStatus(state: const _S(results: 'unsubscribed'))]);
      expect(fired, isEmpty, reason: 'no virtual time passed');
      probe.cancel();
    }, virtualTime: true);

    test(
        'a timer that re-arms itself for ever never goes idle: the settle '
        'fails after five VIRTUAL seconds, which take none', () async {
      final real = Stopwatch()..start();
      late _Shelf shelf;
      await expectLater(
        runJuiceFlow((flow) async {
          shelf = flow.add(_Shelf());
          await flow.send(shelf, _Poll());
        }, virtualTime: true),
        _fails(allOf(
          contains('not idle after 0:00:05.000000 of virtual time'),
          contains('delayed send _Poll to _Shelf (after 0:00:01.000000)'),
        )),
      );
      _expectInstant(real);
      expect(shelf.state.ticks, 5,
          reason: 'at 0, 1, 2, 3 and 4 seconds; at 5 the limit, armed first, '
              'fires first');
      expect(shelf.isClosed, isTrue);
    });

    test('the limit is the one settle was given, on the virtual clock',
        () async {
      await expectLater(
        runJuiceFlow((flow) async {
          final shelf = flow.add(_Shelf(debounce: const Duration(seconds: 30)));
          shelf.typed('too late');
          await flow.settle();
        }, virtualTime: true),
        _fails(contains('not idle after 0:00:05.000000 of virtual time')),
      );

      await runJuiceFlow((flow) async {
        final shelf = flow.add(_Shelf(debounce: const Duration(seconds: 30)));
        shelf.typed('in time');
        await flow.settle(timeout: const Duration(minutes: 1));
        flow.expect(shelf, [_results('in time')]);
      }, virtualTime: true);
    });

    test('exhaustive on the virtual clock too: an unconsumed emission fails',
        () async {
      await expectLater(
        runJuiceFlow((flow) async {
          final shelf = flow.add(_Shelf());
          shelf.typed('unseen');
          await flow.settle();
        }, virtualTime: true),
        _fails(contains('_Shelf emitted 1 status(es) no flow.expect consumed')),
      );
    });

    test("the body's own failure is the one reported", () async {
      final before = JuiceLoggerConfig.logger;
      late _Shelf shelf;
      await expectLater(
        runJuiceFlow((flow) async {
          shelf = flow.add(_Shelf());
          shelf.typed('never asserted');
          await flow.settle();
          throw StateError('mine');
        }, virtualTime: true),
        throwsA(isA<StateError>().having((e) => e.message, 'message', 'mine')),
      );
      expect(shelf.isClosed, isTrue);
      expect(identical(JuiceLoggerConfig.logger, before), isTrue);
      expect(JuiceActivityProbe.current, isNull);
    });

    test('the flow is over, and everything handed back, when it returns',
        () async {
      final before = JuiceLoggerConfig.logger;
      late _Shelf shelf;
      late JuiceFlow leaked;
      await runJuiceFlow((flow) async {
        leaked = flow;
        shelf = flow.register<_Shelf>(() => _Shelf());
        expect(JuiceActivityProbe.current, isNotNull);
      }, virtualTime: true);

      expect(shelf.isClosed, isTrue);
      expect(BlocScope.isRegistered<_Shelf>(), isFalse);
      expect(identical(JuiceLoggerConfig.logger, before), isTrue);
      expect(JuiceActivityProbe.current, isNull);
      expect(() => leaked.elapse(_msec(1)), throwsStateError);
    });

    test('will not start over a used BlocScope, as on the real clock',
        () async {
      BlocScope.register<_Shelf>(() => _Shelf());
      await expectLater(
        runJuiceFlow((flow) async {}, virtualTime: true),
        throwsA(isA<StateError>().having((e) => e.message, 'message',
            contains('BlocScope already holds a registration'))),
      );
      expect(JuiceActivityProbe.current, isNull);
    });
  });

  group('the real world, under virtual time', () {
    test(
        'a test waiting on something no timer will complete fails at once, '
        'saying so — and everything is closed and handed back', () async {
      final before = JuiceLoggerConfig.logger;
      final real = Stopwatch()..start();
      final world = Completer<void>(); // real I/O: nothing virtual ends it
      late _Shelf shelf;
      await expectLater(
        runJuiceFlow((flow) async {
          shelf = flow.register<_Shelf>(() => _Shelf());
          await world.future;
        }, virtualTime: true),
        _fails(allOf(
          contains('under virtual time the test is waiting on something no '
              'timer will complete'),
          contains('In flight: nothing'),
          contains('run this test on the real clock, or fake the seam'),
          isNot(contains('Closing the blocs did not finish')),
        )),
      );
      _expectInstant(real);
      expect(shelf.isClosed, isTrue);
      expect(BlocScope.isRegistered<_Shelf>(), isFalse);
      expect(identical(JuiceLoggerConfig.logger, before), isTrue);
      expect(JuiceActivityProbe.current, isNull);
    });

    test(
        'a use case waiting on the real world: the settle fails after its '
        'virtual limit, naming the send and the reason', () async {
      final real = Stopwatch()..start();
      final world = Completer<void>();
      await expectLater(
        runJuiceFlow((flow) async {
          final shelf = flow.add(_Shelf());
          await flow.send(shelf, _Fetch(world.future));
        }, virtualTime: true),
        _fails(allOf(
          contains('not idle after 0:00:05.000000 of virtual time'),
          contains('send _Fetch to _Shelf'),
          contains('Under virtual time a use case waiting on real I/O'),
        )),
      );
      _expectInstant(real);
    });

    test(
        'beside a periodic timer the clock would jump for ever: the wait is '
        'called stuck after an hour of virtual time', () async {
      final real = Stopwatch()..start();
      final world = Completer<void>();
      late _Ticker ticker;
      await expectLater(
        runJuiceFlow((flow) async {
          ticker = flow.add(_Ticker());
          await world.future;
        }, virtualTime: true),
        _fails(allOf(
          contains('only periodic timers were left beside, for an hour of '
              'virtual time'),
          contains('run this test on the real clock, or fake the seam'),
        )),
      );
      expect(ticker.state.ticks, 3600);
      expect(ticker.isClosed, isTrue);
      expect(real.elapsed, lessThan(const Duration(seconds: 20)));
    });

    test(
        'a close that never finishes is said too, and the logger and the '
        'probe still go back', () async {
      final before = JuiceLoggerConfig.logger;
      final world = Completer<void>();
      await expectLater(
        runJuiceFlow((flow) async {
          flow.add(_CloseHangs());
          await world.future;
        }, virtualTime: true),
        _fails(contains('Closing the blocs did not finish either.')),
      );
      expect(identical(JuiceLoggerConfig.logger, before), isTrue);
      expect(JuiceActivityProbe.current, isNull);
    });

    test('a close that never finishes after a body that did: said the same',
        () async {
      await expectLater(
        runJuiceFlow((flow) async {
          flow.add(_CloseHangs());
        }, virtualTime: true),
        _fails(allOf(
          contains('waiting on something no timer will complete'),
          contains('Closing the blocs did not finish either.'),
        )),
      );
      expect(JuiceActivityProbe.current, isNull);
    });

    juiceFlowTest(
        'the hour beside periodic timers is counted from the last moment '
        'anything else was pending — a long wait on a ticker is not stuck',
        (flow) async {
      final ticker = flow.add(_Ticker());

      // Forty minutes with nothing pending but the ticker…
      await ticker.stream.firstWhere((s) => s.state.ticks == 2400);
      // …a timer of the test's own…
      await flow.elapse(const Duration(milliseconds: 1));
      // …and forty more: eighty in all, never an hour at a stretch.
      await ticker.stream.firstWhere((s) => s.state.ticks == 4800);
      await flow.settle();

      flow.expect(ticker, hasLength(4800));
    }, virtualTime: true);
  });

  group('elapse', () {
    juiceFlowTest('time cannot run backwards', (flow) async {
      expect(
        () => flow.elapse(const Duration(milliseconds: -1)),
        throwsA(isA<ArgumentError>()
            .having((e) => e.name, 'name', 'duration')
            .having((e) => e.message, 'message',
                'juiceFlowTest: time cannot run backwards')),
      );
    });
  });
}
