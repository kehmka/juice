import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';
import '../support/capture_logger.dart';

/// `Reaction` and `JuiceBloc.react`: one bloc reacting to another's state.
/// The destination owns the reaction; it sees state only; the edge is
/// judged on the emission and the event is sent a microtask later; attach
/// is explicit ([AtAttach]); a chain past `Reaction.maxHops` is refused;
/// the reaction's own failures are recorded and never reach the emitter.

class _S extends BlocState {
  const _S({this.n = 0, this.ready = false, this.other = 0});
  final int n;
  final bool ready;
  final int other;
}

class _Set extends EventBase {
  _Set({this.n, this.ready, this.other});
  final int? n;
  final bool? ready;
  final int? other;
}

/// Two state changes in one tick.
class _Twice extends EventBase {}

/// A waiting emission, then a failure emission, each changing `n`.
class _Kinds extends EventBase {}

/// Changes `n`, then re-emits an event: the re-emission is no transition.
class _SetThenReEmit extends EventBase {}

class _Marker extends EventBase {}

/// An update that changes nothing.
class _Touch extends EventBase {}

class _SetUC extends BlocUseCase<_Src, _Set> {
  @override
  Future<void> execute(_Set e) async => emitUpdate(
      newState: _S(
          n: e.n ?? bloc.state.n,
          ready: e.ready ?? bloc.state.ready,
          other: e.other ?? bloc.state.other));
}

class _TwiceUC extends BlocUseCase<_Src, _Twice> {
  @override
  Future<void> execute(_Twice e) async {
    emitUpdate(newState: const _S(n: 1));
    emitUpdate(newState: const _S(n: 2));
  }
}

class _KindsUC extends BlocUseCase<_Src, _Kinds> {
  @override
  Future<void> execute(_Kinds e) async {
    emitWaiting(newState: const _S(n: 10));
    emitFailure(newState: const _S(n: 20), error: StateError('boom'));
  }
}

class _SetThenReEmitUC extends BlocUseCase<_Src, _SetThenReEmit> {
  @override
  Future<void> execute(_SetThenReEmit e) async {
    emitUpdate(newState: const _S(n: 5));
    emitEvent(event: _Marker());
    emitEvent(event: _Marker());
  }
}

class _TouchUC extends BlocUseCase<_Src, _Touch> {
  @override
  Future<void> execute(_Touch e) async => emitUpdate();
}

List<UseCaseBuilderGenerator> _srcBuilders<B extends JuiceBloc<_S>>() => [
      () => UseCaseBuilder(
          typeOfEvent: _Set,
          useCaseGenerator: () => _SetUC(),
          concurrency: EventConcurrency.sequential),
      () => UseCaseBuilder(
          typeOfEvent: _Twice,
          useCaseGenerator: () => _TwiceUC(),
          concurrency: EventConcurrency.sequential),
      () => UseCaseBuilder(
          typeOfEvent: _Kinds,
          useCaseGenerator: () => _KindsUC(),
          concurrency: EventConcurrency.sequential),
      () => UseCaseBuilder(
          typeOfEvent: _SetThenReEmit,
          useCaseGenerator: () => _SetThenReEmitUC(),
          concurrency: EventConcurrency.sequential),
      () => UseCaseBuilder(
          typeOfEvent: _Touch,
          useCaseGenerator: () => _TouchUC(),
          concurrency: EventConcurrency.sequential),
    ];

class _Src extends JuiceBloc<_S> {
  _Src({JuiceLogger? logger, _S initial = const _S()})
      : super(initial, _srcBuilders(), const [], logger ?? CaptureLogger(),
            quietErrorHandler);
}

/// A second source TYPE, for the tests that resolve by type.
class _LeasedSrc extends _Src {}

class _ScopedSrc extends _Src {}

/// What the destination was told, in order.
class _Log extends BlocState {
  const _Log([this.got = const []]);
  final List<String> got;
}

class _Got extends EventBase {
  _Got(this.label);
  final String label;
}

/// Not handled by the destination.
class _Nope extends EventBase {}

class _GotUC extends BlocUseCase<_Dst, _Got> {
  @override
  Future<void> execute(_Got e) async =>
      emitUpdate(newState: _Log([...bloc.state.got, e.label]));
}

class _Dst extends JuiceBloc<_Log> {
  _Dst({JuiceLogger? logger})
      : super(
          const _Log(),
          [
            () => UseCaseBuilder.typed(() => _GotUC(),
                concurrency: EventConcurrency.sequential),
          ],
          const [],
          logger ?? CaptureLogger(),
          quietErrorHandler,
        );
}

/// A destination wired in its own constructor body.
class _Wired extends _Dst {
  _Wired(_Src source) {
    react(Reaction<_Src, _S>.becomes(
      (s) => s.ready,
      source: source,
      send: (s) => _Got('ready'),
      atAttach: AtAttach.catchUp,
    ));
  }
}

/// A counter that can sit anywhere in a chain or a ring.
class _N extends BlocState {
  const _N(this.n);
  final int n;
}

class _Bump extends EventBase {}

class _BumpUC extends BlocUseCase<_Counter, _Bump> {
  @override
  Future<void> execute(_Bump e) async {
    // A ring whose bound did not hold never yields to the event loop: the
    // test would spin until it ran out of memory instead of failing. Past
    // any count a correct bound allows, stop feeding it.
    if (bloc.state.n >= 40) {
      throw StateError('runaway ring: the hop bound did not hold');
    }
    emitUpdate(newState: _N(bloc.state.n + 1));
  }
}

class _Counter extends JuiceBloc<_N> {
  _Counter(this.name, JuiceLogger logger)
      : super(
          const _N(0),
          [
            () => UseCaseBuilder.typed(() => _BumpUC(),
                concurrency: EventConcurrency.sequential),
          ],
          const [],
          logger,
          quietErrorHandler,
        );
  final String name;
}

/// `to` bumps whenever `from`'s count changes.
ReactionBinding _follow(_Counter to, _Counter from) =>
    to.react(Reaction<_Counter, _N>.changes(
      (s) => s.n,
      source: from,
      send: (s) => _Bump(),
      atAttach: AtAttach.skip,
    ));

void main() {
  late JuiceLogger savedLogger;
  late Level savedLevel;
  setUp(() {
    savedLogger = JuiceLoggerConfig.logger;
    savedLevel = JuiceLoggerConfig.minLevel;
    JuiceLoggerConfig.minLevel = Level.all;
  });
  tearDown(() async {
    JuiceLoggerConfig.configureLogger(savedLogger);
    JuiceLoggerConfig.minLevel = savedLevel;
    await BlocScope.reset();
  });

  group('the three forms', () {
    test('becomes: fires when the predicate goes false → true, only then',
        () async {
      final src = _Src();
      final dst = _Dst();
      dst.react(Reaction<_Src, _S>.becomes(
        (s) => s.ready,
        source: src,
        send: (s) => _Got('ready@${s.n}'),
        atAttach: AtAttach.skip,
      ));
      await src.send(_Set(n: 1)); // predicate still false
      await src.send(_Set(ready: true)); // false → true
      await src.send(_Set(n: 2)); // true → true
      await src.send(_Set(ready: false)); // true → false
      await src.send(_Set(n: 3, ready: true)); // false → true again
      await pump();
      expect(dst.state.got, ['ready@1', 'ready@3']);
      await dst.close();
      await src.close();
    });

    test('changes: fires when the selected value changes, not otherwise',
        () async {
      final src = _Src();
      final dst = _Dst();
      dst.react(Reaction<_Src, _S>.changes(
        (s) => s.n,
        source: src,
        send: (s) => _Got('n=${s.n}'),
        atAttach: AtAttach.skip,
      ));
      await src.send(_Set(n: 1));
      await src.send(_Set(other: 9)); // another field
      await src.send(_Set(n: 1)); // the same value again
      await src.send(_Touch()); // an update that changes nothing
      await src.send(_Set(n: 2));
      await pump();
      expect(dst.state.got, ['n=1', 'n=2']);
      await dst.close();
      await src.close();
    });

    test('edge: any edge stated over the old and the new state', () async {
      final src = _Src();
      final dst = _Dst();
      dst.react(Reaction<_Src, _S>.edge(
        (old, now) => now.n > old.n + 1, // a jump of more than one
        source: src,
        send: (s) => _Got('jumped to ${s.n}'),
      ));
      await src.send(_Set(n: 1));
      await src.send(_Set(n: 5));
      await src.send(_Set(n: 6));
      await pump();
      expect(dst.state.got, ['jumped to 5']);
      await dst.close();
      await src.close();
    });

    test(
        'two changes in one tick are two hops, each sent the state it fired '
        'on, in order', () async {
      final src = _Src();
      final dst = _Dst();
      dst.react(Reaction<_Src, _S>.changes(
        (s) => s.n,
        source: src,
        send: (s) => _Got('n=${s.n}'),
        atAttach: AtAttach.skip,
      ));
      await src.send(_Twice());
      await pump();
      expect(dst.state.got, ['n=1', 'n=2']);
      await dst.close();
      await src.close();
    });

    test('every status kind is observed: a waiting and a failure emission',
        () async {
      final src = _Src();
      final dst = _Dst();
      dst.react(Reaction<_Src, _S>.changes(
        (s) => s.n,
        source: src,
        send: (s) => _Got('n=${s.n}'),
        atAttach: AtAttach.skip,
      ));
      await src.send(_Kinds());
      await pump();
      expect(dst.state.got, ['n=10', 'n=20']);
      await dst.close();
      await src.close();
    });

    test('a re-emitted event is not a transition: it does not fire again',
        () async {
      final src = _Src();
      final dst = _Dst();
      dst.react(Reaction<_Src, _S>.changes(
        (s) => s.n,
        source: src,
        send: (s) => _Got('n=${s.n}'),
        atAttach: AtAttach.skip,
      ));
      await src.send(_SetThenReEmit());
      await pump();
      expect(dst.state.got, ['n=5'],
          reason: 'the two emitEvent re-emissions repeat the same states');
      await dst.close();
      await src.close();
    });
  });

  group('when the event is sent', () {
    test(
        'the edge is judged on the emission; the event is built and sent a '
        'microtask later, never inside the emit', () async {
      final src = _Src();
      final dst = _Dst();
      var built = 0;
      dst.react(Reaction<_Src, _S>.changes(
        (s) => s.n,
        source: src,
        send: (s) {
          built++;
          return _Got('n=${s.n}');
        },
        atAttach: AtAttach.skip,
      ));
      src.seedState(const _S(n: 1)); // a synchronous emission
      expect(built, 0, reason: 'send did not run inside the emit');
      expect(dst.state.got, isEmpty);
      await Future<void>.microtask(() {});
      expect(built, 1);
      await pump();
      expect(dst.state.got, ['n=1']);
      await dst.close();
      await src.close();
    });
  });

  group('attach', () {
    test('skip: the state at attach does not count', () async {
      final src = _Src(initial: const _S(n: 4, ready: true));
      final dst = _Dst();
      dst.react(Reaction<_Src, _S>.becomes(
        (s) => s.ready,
        source: src,
        send: (s) => _Got('ready'),
        atAttach: AtAttach.skip,
      ));
      dst.react(Reaction<_Src, _S>.changes(
        (s) => s.n,
        source: src,
        send: (s) => _Got('n=${s.n}'),
        atAttach: AtAttach.skip,
      ));
      await pump();
      expect(dst.state.got, isEmpty);
      await src.send(_Set(ready: false));
      await src.send(_Set(ready: true));
      await pump();
      expect(dst.state.got, ['ready']);
      await dst.close();
      await src.close();
    });

    test(
        'catchUp, becomes: fires once if the predicate holds now — as an '
        'ordinary hop, a microtask after the attach', () async {
      final log = CaptureLogger();
      final src = _Src(initial: const _S(ready: true));
      final dst = _Dst(logger: log);
      dst.react(Reaction<_Src, _S>.becomes(
        (s) => s.ready,
        source: src,
        send: (s) => _Got('ready'),
        atAttach: AtAttach.catchUp,
      ));
      expect(dst.state.got, isEmpty, reason: 'never synchronously');
      expect(log.where('reaction', 'fire'), isEmpty);
      await pump();
      expect(dst.state.got, ['ready']);
      final fired = log.where('reaction', 'fire').single;
      expect(fired['reason'], 'attach');
      expect(fired['hopDepth'], 1);
      expect(fired.containsKey('causeExecutionId'), isFalse,
          reason: 'no run made the state it caught up on');
      // It is attached like any other: the next false → true fires too.
      await src.send(_Set(ready: false));
      await src.send(_Set(ready: true));
      await pump();
      expect(dst.state.got, ['ready', 'ready']);
      await dst.close();
      await src.close();
    });

    test('catchUp, becomes: does not fire if the predicate does not hold',
        () async {
      final src = _Src();
      final dst = _Dst();
      dst.react(Reaction<_Src, _S>.becomes(
        (s) => s.ready,
        source: src,
        send: (s) => _Got('ready'),
        atAttach: AtAttach.catchUp,
      ));
      await pump();
      expect(dst.state.got, isEmpty);
      await dst.close();
      await src.close();
    });

    test('catchUp, changes: fires once with the current state', () async {
      final src = _Src(initial: const _S(n: 7));
      final dst = _Dst();
      dst.react(Reaction<_Src, _S>.changes(
        (s) => s.n,
        source: src,
        send: (s) => _Got('n=${s.n}'),
        atAttach: AtAttach.catchUp,
      ));
      await pump();
      expect(dst.state.got, ['n=7']);
      await dst.close();
      await src.close();
    });

    test('edge takes no AtAttach and never fires at attach', () async {
      final src = _Src(initial: const _S(n: 7));
      final dst = _Dst();
      final reaction = Reaction<_Src, _S>.edge(
        (old, now) => true,
        source: src,
        send: (s) => _Got('edge'),
      );
      expect(reaction.atAttach, isNull);
      expect(reaction.firesAtAttach(src.state), isFalse,
          reason: 'even if asked: there is no old state to compare');
      dst.react(reaction);
      await pump();
      expect(dst.state.got, isEmpty);
      await dst.close();
      await src.close();
    });

    test(
        'react in a constructor body: the catch-up arrives after '
        'construction', () async {
      final src = _Src(initial: const _S(ready: true));
      final dst = _Wired(src);
      expect(dst.state.got, isEmpty);
      await pump();
      expect(dst.state.got, ['ready']);
      await dst.close();
      await src.close();
    });

    test('a catch-up whose destination closes first is discarded', () async {
      final src = _Src(initial: const _S(ready: true));
      final dst = _Dst();
      var built = 0;
      dst.react(Reaction<_Src, _S>.becomes(
        (s) => s.ready,
        source: src,
        send: (s) {
          built++;
          return _Got('ready');
        },
        atAttach: AtAttach.catchUp,
      ));
      await dst.close();
      await pump();
      expect(built, 0);
      await src.close();
    });
  });

  group('the source', () {
    test('by type: the registered bloc, created on demand', () async {
      BlocScope.register<_Src>(() => _Src());
      final dst = _Dst();
      dst.react(Reaction<_Src, _S>.changes(
        (s) => s.n,
        send: (s) => _Got('n=${s.n}'),
        atAttach: AtAttach.skip,
      ));
      await BlocScope.get<_Src>().send(_Set(n: 3));
      await pump();
      expect(dst.state.got, ['n=3']);
      await dst.close();
    });

    test('by type, in a scope', () async {
      BlocScope.register<_ScopedSrc>(() => _ScopedSrc(), scope: 'left');
      final dst = _Dst();
      dst.react(Reaction<_ScopedSrc, _S>.changes(
        (s) => s.n,
        scope: 'left',
        send: (s) => _Got('n=${s.n}'),
        atAttach: AtAttach.skip,
      ));
      await BlocScope.get<_ScopedSrc>(scope: 'left').send(_Set(n: 8));
      await pump();
      expect(dst.state.got, ['n=8']);
      await dst.close();
    });

    test('an instance AND a scope is an ArgumentError', () {
      final src = _Src();
      expect(
          () => Reaction<_Src, _S>.changes(
                (s) => s.n,
                source: src,
                scope: 'left',
                send: (s) => _Got('x'),
                atAttach: AtAttach.skip,
              ),
          throwsArgumentError);
    });

    test('an unregistered type throws at attach', () async {
      final dst = _Dst();
      expect(
          () => dst.react(Reaction<_Src, _S>.changes(
                (s) => s.n,
                send: (s) => _Got('x'),
                atAttach: AtAttach.skip,
              )),
          throwsStateError);
      await dst.close();
    });

    test(
        'a leased bloc cannot be resolved by type (a reaction holds no '
        'lease); by instance it attaches and takes no lease', () async {
      BlocScope.register<_LeasedSrc>(() => _LeasedSrc(),
          lifecycle: BlocLifecycle.leased);
      final dst = _Dst();
      expect(
          () => dst.react(Reaction<_LeasedSrc, _S>.changes(
                (s) => s.n,
                send: (s) => _Got('x'),
                atAttach: AtAttach.skip,
              )),
          // The reaction's OWN refusal, which holds in every build mode —
          // not BlocScope.get's, which throws in debug only.
          throwsA(isA<StateError>().having(
              (e) => e.message, 'message', contains('holds no lease'))));
      expect(BlocScope.diagnostics<_LeasedSrc>()!.isActive, isFalse,
          reason: 'the refusal did not create it');

      final lease = BlocScope.lease<_LeasedSrc>();
      final binding = dst.react(Reaction<_LeasedSrc, _S>.changes(
        (s) => s.n,
        source: lease.bloc,
        send: (s) => _Got('n=${s.n}'),
        atAttach: AtAttach.skip,
      ));
      expect(BlocScope.diagnostics<_LeasedSrc>()!.leaseCount, 1,
          reason: 'only the test\'s own lease');
      await lease.bloc.send(_Set(n: 2));
      await pump();
      expect(dst.state.got, ['n=2']);

      // The last lease goes: the source closes, and the reaction with it.
      lease.dispose();
      await pump(3);
      expect(binding.isActive, isFalse);
      await dst.close();
    });

    test('a closed source throws at attach', () async {
      final src = _Src();
      await src.close();
      final dst = _Dst();
      expect(
          () => dst.react(Reaction<_Src, _S>.changes(
                (s) => s.n,
                source: src,
                send: (s) => _Got('x'),
                atAttach: AtAttach.skip,
              )),
          throwsA(isA<StateError>()
              .having((e) => e.message, 'message', contains('source'))));
      await dst.close();
    });

    test('a closing source throws at attach', () async {
      final src = _Src();
      final closing = src.close();
      final dst = _Dst();
      expect(
          () => dst.react(Reaction<_Src, _S>.changes(
                (s) => s.n,
                source: src,
                send: (s) => _Got('x'),
                atAttach: AtAttach.skip,
              )),
          throwsStateError);
      await closing;
      await dst.close();
    });

    test('react on a closed or closing destination throws', () async {
      final src = _Src();
      final reaction = Reaction<_Src, _S>.changes(
        (s) => s.n,
        source: src,
        send: (s) => _Got('x'),
        atAttach: AtAttach.skip,
      );
      final closingDst = _Dst();
      final closing = closingDst.close();
      expect(() => closingDst.react(reaction), throwsStateError);
      await closing;
      expect(
          () => closingDst.react(reaction),
          throwsA(isA<StateError>().having(
              (e) => e.message, 'message', contains('closed or closing'))));
      await src.close();
    });
  });

  group('how a reaction ends', () {
    test('the destination closes: it ends, silently', () async {
      final log = CaptureLogger();
      final src = _Src();
      final dst = _Dst(logger: log);
      var judged = 0;
      final binding = dst.react(Reaction<_Src, _S>.changes(
        (s) {
          judged++;
          return s.n;
        },
        source: src,
        send: (s) => _Got('x'),
        atAttach: AtAttach.skip,
      ));
      expect(binding.isActive, isTrue);
      await dst.close();
      expect(binding.isActive, isFalse);
      expect(log.typed('reaction'), isEmpty);
      await src.send(_Set(n: 1));
      expect(judged, 0, reason: 'the tap on the source is gone');
      await src.close();
    });

    test(
        'the source closes: it ends and says so (reaction / end), and a new '
        'instance of the source is not picked up', () async {
      final log = CaptureLogger();
      final src = _Src();
      final dst = _Dst(logger: log);
      final binding = dst.react(Reaction<_Src, _S>.changes(
        (s) => s.n,
        source: src,
        send: (s) => _Got('n=${s.n}'),
        atAttach: AtAttach.skip,
      ));
      await src.close();
      expect(binding.isActive, isFalse);
      final ended = log.where('reaction', 'end').single;
      expect(ended['sourceBloc'], '_Src');
      expect(ended['destBloc'], '_Dst');
      expect(ended['reaction'], 'changes');
      expect(ended['reason'], 'source closed');
      expect(ended['level'], Level.info);

      final again = _Src();
      await again.send(_Set(n: 1));
      await pump();
      expect(dst.state.got, isEmpty);
      await again.close();
      await dst.close();
    });

    test('below the floor the end is not recorded, and it still ends',
        () async {
      final log = CaptureLogger();
      JuiceLoggerConfig.minLevel = Level.warning;
      final src = _Src();
      final dst = _Dst(logger: log);
      final binding = dst.react(Reaction<_Src, _S>.changes(
        (s) => s.n,
        source: src,
        send: (s) => _Got('x'),
        atAttach: AtAttach.skip,
      ));
      await src.close();
      expect(binding.isActive, isFalse);
      expect(log.typed('reaction'), isEmpty);
      await dst.close();
    });

    test(
        'cancel: idempotent; a hop decided but not yet sent is discarded, '
        'with no record', () async {
      final log = CaptureLogger();
      final src = _Src();
      final dst = _Dst(logger: log);
      var built = 0;
      final binding = dst.react(Reaction<_Src, _S>.changes(
        (s) => s.n,
        source: src,
        send: (s) {
          built++;
          return _Got('x');
        },
        atAttach: AtAttach.skip,
      ));
      src.seedState(const _S(n: 1)); // the hop is decided, not yet sent
      binding.cancel();
      binding.cancel();
      expect(binding.isActive, isFalse);
      await pump();
      expect(built, 0);
      expect(dst.state.got, isEmpty);
      expect(log.typed('reaction'), isEmpty);
      await src.send(_Set(n: 2));
      await pump();
      expect(dst.state.got, isEmpty);
      // Both blocs still close cleanly with the reaction already gone.
      await dst.close();
      await src.close();
    });
  });

  group('a reaction\'s own failures', () {
    test(
        'a predicate that throws: recorded with its site, the emitting use '
        'case untouched, the reaction still attached', () async {
      final log = CaptureLogger();
      final srcLog = CaptureLogger();
      final src = _Src(logger: srcLog);
      final dst = _Dst(logger: log);
      var thrown = false;
      final binding = dst.react(Reaction<_Src, _S>.becomes(
        (s) {
          // Throws once, on the first state it is asked about.
          if (!thrown) {
            thrown = true;
            throw ArgumentError('bad predicate');
          }
          return s.ready;
        },
        source: src,
        send: (s) => _Got('ready'),
        atAttach: AtAttach.skip,
      ));
      await src.send(_Set(n: 1));
      expect(src.state.n, 1, reason: 'the emit went through');
      expect(srcLog.typed('use_case_error'), isEmpty);
      final failed = log.where('reaction', 'error').single;
      expect(failed['site'], 'predicate');
      expect(failed['error'], isA<ArgumentError>());
      expect(failed['sourceBloc'], '_Src');
      expect(failed['destBloc'], '_Dst');
      expect(failed['reaction'], 'becomes');
      expect(failed['level'], Level.error);
      expect(binding.isActive, isTrue);

      await src.send(_Set(n: 2, ready: true));
      await pump();
      expect(dst.state.got, ['ready']);
      await dst.close();
      await src.close();
    });

    test('select and edge name their own site', () async {
      final log = CaptureLogger();
      final src = _Src();
      final dst = _Dst(logger: log);
      dst.react(Reaction<_Src, _S>.changes(
        (s) => throw StateError('bad select'),
        source: src,
        send: (s) => _Got('x'),
        atAttach: AtAttach.skip,
      ));
      dst.react(Reaction<_Src, _S>.edge(
        (old, now) => throw StateError('bad edge'),
        source: src,
        send: (s) => _Got('x'),
      ));
      await src.send(_Set(n: 1));
      expect(log.where('reaction', 'error').map((e) => e['site']),
          unorderedEquals(['select', 'edge']));
      await dst.close();
      await src.close();
    });

    test('a send that throws: recorded, nothing sent, still attached',
        () async {
      final log = CaptureLogger();
      final src = _Src();
      final dst = _Dst(logger: log);
      dst.react(Reaction<_Src, _S>.changes(
        (s) => s.n,
        source: src,
        send: (s) => s.n == 1 ? throw StateError('bad send') : _Got('n=${s.n}'),
        atAttach: AtAttach.skip,
      ));
      await src.send(_Set(n: 1));
      await pump();
      final failed = log.where('reaction', 'error').single;
      expect(failed['site'], 'send');
      expect(log.where('reaction', 'fire'), isEmpty);
      await src.send(_Set(n: 2));
      await pump();
      expect(dst.state.got, ['n=2']);
      await dst.close();
      await src.close();
    });

    test(
        'a predicate that throws at a catch-up attach: recorded; react '
        'still returns a live reaction', () async {
      final log = CaptureLogger();
      final src = _Src(initial: const _S(n: 1));
      final dst = _Dst(logger: log);
      final binding = dst.react(Reaction<_Src, _S>.becomes(
        (s) => s.n == 1 ? throw ArgumentError('bad predicate') : s.ready,
        source: src,
        send: (s) => _Got('ready'),
        atAttach: AtAttach.catchUp,
      ));
      expect(binding.isActive, isTrue);
      expect(log.where('reaction', 'error').single['site'], 'predicate');
      await pump();
      expect(dst.state.got, isEmpty);
      await dst.close();
      await src.close();
    });

    test('a failure is recorded whatever the telemetry floor', () async {
      final log = CaptureLogger();
      JuiceLoggerConfig.minLevel = Level.warning;
      final src = _Src();
      final dst = _Dst(logger: log);
      dst.react(Reaction<_Src, _S>.changes(
        (s) => throw StateError('bad select'),
        source: src,
        send: (s) => _Got('x'),
        atAttach: AtAttach.skip,
      ));
      await src.send(_Set(n: 1));
      expect(log.where('reaction', 'error'), hasLength(1));
      await dst.close();
      await src.close();
    });

    test(
        'an event the destination has no use case for is an unhandled '
        'event, as from any send', () async {
      final log = CaptureLogger();
      final src = _Src();
      final dst = _Dst(logger: log);
      dst.react(Reaction<_Src, _S>.changes(
        (s) => s.n,
        source: src,
        send: (s) => _Nope(),
        atAttach: AtAttach.skip,
      ));
      await src.send(_Set(n: 1));
      await pump();
      expect(log.typed('unhandled_event').single['event'], '_Nope');
      await dst.close();
      await src.close();
    });
  });

  group('the chain: cause, depth and the bound', () {
    test(
        'a → b → c: each hop names the run it came from and how deep it is, '
        'and the run it causes says the same', () async {
      final log = CaptureLogger();
      final a = _Counter('a', log);
      final b = _Counter('b', log);
      final c = _Counter('c', log);
      _follow(b, a);
      _follow(c, b);
      await a.send(_Bump());
      await pump(3);
      expect([a.state.n, b.state.n, c.state.n], [1, 1, 1]);

      final runs = log.typed('use_case_execution').toList();
      expect(runs, hasLength(3));
      final hops = log.where('reaction', 'fire').toList();
      expect(hops.map((e) => e['hopDepth']), [1, 2]);
      // Hop 1 came from a's run; the run it started in b says so.
      expect(hops[0]['causeExecutionId'], runs[0]['executionId']);
      expect(runs[0].containsKey('causeExecutionId'), isFalse,
          reason: 'nothing caused the first run');
      expect(runs[1]['causeExecutionId'], runs[0]['executionId']);
      expect(runs[1]['hopDepth'], 1);
      // Hop 2 came from b's run; c's run says so.
      expect(hops[1]['causeExecutionId'], runs[1]['executionId']);
      expect(runs[2]['causeExecutionId'], runs[1]['executionId']);
      expect(runs[2]['hopDepth'], 2);
      expect(hops.map((e) => e['event']), ['_Bump', '_Bump']);
      expect(hops.map((e) => e['reaction']), ['changes', 'changes']);
      for (final bloc in [a, b, c]) {
        await bloc.close();
      }
    });

    test(
        'a ring is cut at Reaction.maxHops: eight hops are sent, the ninth '
        'is refused and recorded as an error, and the reactions stay',
        () async {
      expect(Reaction.maxHops, 8);
      final log = CaptureLogger();
      final a = _Counter('a', log);
      final b = _Counter('b', log);
      final ab = _follow(b, a);
      final ba = _follow(a, b);
      await a.send(_Bump());
      await pump(20);
      // The kick, then eight hops.
      expect(a.state.n + b.state.n, 9);
      expect(log.where('reaction', 'fire').map((e) => e['hopDepth']),
          [1, 2, 3, 4, 5, 6, 7, 8]);
      final refused = log.where('reaction', 'refused').single;
      expect(refused['hopDepth'], 9);
      expect(refused['level'], Level.error);
      expect(refused['error'], isA<StateError>());
      expect(refused['sourceBloc'], '_Counter');
      expect(refused['destBloc'], '_Counter');
      expect(refused['reaction'], 'changes');
      expect([ab.isActive, ba.isActive], [true, true]);

      // A new, independent emission starts a new chain at depth 1.
      await a.send(_Bump());
      await pump(20);
      expect(a.state.n + b.state.n, 18);
      expect(log.where('reaction', 'refused'), hasLength(2));
      await a.close();
      await b.close();
    });

    test('a refusal is recorded whatever the telemetry floor', () async {
      final log = CaptureLogger();
      JuiceLoggerConfig.minLevel = Level.warning;
      final a = _Counter('a', log);
      final b = _Counter('b', log);
      _follow(b, a);
      _follow(a, b);
      await a.send(_Bump());
      await pump(20);
      expect(log.where('reaction', 'refused'), hasLength(1));
      expect(log.where('reaction', 'fire'), isEmpty,
          reason: 'the hops themselves are chatter');
      expect(a.state.n + b.state.n, 9, reason: 'the bound holds all the same');
      await a.close();
      await b.close();
    });
  });
}
