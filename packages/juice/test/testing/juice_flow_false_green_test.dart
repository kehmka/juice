import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';
import 'package:juice/src/bloc/src/core/activity_probe.dart';
import 'package:juice/testing.dart';
import '../support/capture_logger.dart';

/// The ways a `juiceFlowTest` could PASS when it should fail — and could
/// leave a failing test's state to the next one — found by the 2026-11-11
/// review of the 2.1 branch, each reproduced before it was fixed.

class _S extends BlocState {
  const _S(this.n);
  final int n;
  @override
  bool operator ==(Object other) => other is _S && other.n == n;
  @override
  int get hashCode => n.hashCode;
  @override
  String toString() => '_S($n)';
}

class _Set extends EventBase {
  _Set(this.n);
  final int n;
}

class _Boom extends EventBase {}

class _FireAndForget extends EventBase {}

class _ThrowLater extends EventBase {}

class _Poll extends EventBase {}

/// Does nothing, emits nothing.
class _Noop extends EventBase {}

class _SetUseCase extends BlocUseCase<_Counter, _Set> {
  @override
  Future<void> execute(_Set event) async => emitUpdate(newState: _S(event.n));
}

/// Throws the SAME error object on every run.
class _BoomUseCase extends BlocUseCase<_Counter, _Boom> {
  @override
  Future<void> execute(_Boom event) async =>
      throw const FormatException('the same error, every time');
}

class _FireAndForgetUseCase extends BlocUseCase<_Counter, _FireAndForget> {
  @override
  Future<void> execute(_FireAndForget event) async {
    unawaited(Future<void>.delayed(const Duration(milliseconds: 20))
        .then((_) => bloc.send(_Set(9))));
  }
}

class _ThrowLaterUseCase extends BlocUseCase<_Counter, _ThrowLater> {
  @override
  Future<void> execute(_ThrowLater event) async {
    unawaited(Future<void>.delayed(
        const Duration(seconds: 1), () => throw StateError('lost')));
  }
}

class _PollUseCase extends BlocUseCase<_Counter, _Poll> {
  @override
  Future<void> execute(_Poll event) async =>
      bloc.sendAfter(_Poll(), const Duration(seconds: 1), key: 'poll');
}

class _NoopUseCase extends BlocUseCase<_Counter, _Noop> {
  @override
  Future<void> execute(_Noop event) async {}
}

class _Counter extends JuiceBloc<_S> {
  _Counter()
      : super(const _S(0), [
          () => UseCaseBuilder(
              typeOfEvent: _Set,
              useCaseGenerator: () => _SetUseCase(),
              concurrency: EventConcurrency.concurrent),
          () => UseCaseBuilder(
              typeOfEvent: _Boom,
              useCaseGenerator: () => _BoomUseCase(),
              concurrency: EventConcurrency.concurrent),
          () => UseCaseBuilder(
              typeOfEvent: _FireAndForget,
              useCaseGenerator: () => _FireAndForgetUseCase(),
              concurrency: EventConcurrency.concurrent),
          () => UseCaseBuilder(
              typeOfEvent: _ThrowLater,
              useCaseGenerator: () => _ThrowLaterUseCase(),
              concurrency: EventConcurrency.concurrent),
          () => UseCaseBuilder(
              typeOfEvent: _Noop,
              useCaseGenerator: () => _NoopUseCase(),
              concurrency: EventConcurrency.concurrent),
          () => UseCaseBuilder(
              typeOfEvent: _Poll,
              useCaseGenerator: () => _PollUseCase(),
              concurrency: EventConcurrency.concurrent),
        ]);
}

class _Other extends _Counter {}

Matcher _fails(Object message) =>
    throwsA(isA<TestFailure>().having((f) => f.message, 'message', message));

Future<void> _hops(int k) async {
  for (var i = 0; i < k; i++) {
    await null;
  }
}

void main() {
  late JuiceLogger saved;
  setUp(() {
    saved = JuiceLoggerConfig.logger;
    JuiceLoggerConfig.configureLogger(CaptureLogger());
  });
  tearDown(() => JuiceLoggerConfig.configureLogger(saved));

  group('every error is claimed, the same object or not', () {
    test('the same error object failing two runs is two errors', () async {
      await runJuiceFlow((flow) async {
        final c = flow.add(_Counter());
        await flow.send(c, _Boom());
        await flow.send(c, _Boom());
        flow.expectErrors([isA<FormatException>(), isA<FormatException>()]);
        flow.expect(c, isEmpty);
      });
    });

    test('claimed once, the same object failing again must be claimed again',
        () async {
      await expectLater(
        runJuiceFlow((flow) async {
          final c = flow.add(_Counter());
          await flow.send(c, _Boom());
          flow.expectErrors([isA<FormatException>()]);
          await flow.send(c, _Boom());
        }),
        _fails(contains('unexpected error(s)')),
      );
    });

    test('one stream error reaching two bound blocs is two errors', () async {
      await runJuiceFlow((flow) async {
        final a = flow.add(_Counter());
        final b = flow.add(_Other());
        final source = StreamController<int>.broadcast();
        a.bindStream<int>(source.stream, (_) {});
        b.bindStream<int>(source.stream, (_) {});
        source.addError(StateError('shared'));
        await flow.settle();
        flow.expectErrors([isA<StateError>(), isA<StateError>()]);
        await source.close();
      });
    });

    test('a use case that throws is still ONE error (its echo is dropped)',
        () async {
      await runJuiceFlow((flow) async {
        final c = flow.add(_Counter());
        await flow.send(c, _Boom());
        flow.expectErrors([isA<FormatException>()]);
      });
    });
  });

  group('work after the body', () {
    for (final virtualTime in [false, true]) {
      for (final hops in [1, 5, 12]) {
        test(
            'a stream item still on its way when the body ends fails the '
            'flow ($hops microtask hops, virtualTime: $virtualTime)', () async {
          late _Counter b;
          await expectLater(
            runJuiceFlow((flow) async {
              final source = StreamController<int>.broadcast();
              b = flow.add(_Counter());
              flow.add(_Other()); // closed before b
              b.bindStream<int>(source.stream.asyncMap((n) async {
                await _hops(hops);
                return n;
              }), (n) => b.send(_Set(n)));
              source.add(5); // the last step, with no settle
            }, virtualTime: virtualTime),
            _fails(anyOf(
              contains('still in flight when the test ended'),
              contains('work began after the test body ended'),
            )),
          );
        });
      }
    }

    /// Bloc [b] is bound to a stream fed when bloc [a]'s binding is
    /// cancelled — so [a]'s close, which the flow does after the body,
    /// sets off work in [b], which closes after it.
    Future<void> closeSetsOff(
        JuiceFlow flow, EventBase Function() event) async {
      final fed = StreamController<int>.broadcast();
      final b = flow.add(_Counter());
      final a = flow.add(_Other()); // added last: closed first
      a.bindStream<int>(
          StreamController<int>(onCancel: () => fed.add(1)).stream, (_) {});
      b.bindStream<int>(fed.stream, (_) => b.send(event()));
      await flow.settle();
    }

    test('work another bloc\'s close sets off fails the flow', () async {
      await expectLater(
        runJuiceFlow((flow) => closeSetsOff(flow, _Noop.new)),
        _fails(contains('began while the blocs were closing')),
      );
    });

    test('an emission made while another bloc closes must be consumed',
        () async {
      await expectLater(
        runJuiceFlow((flow) => closeSetsOff(flow, () => _Set(7))),
        _fails(contains('no flow.expect consumed')),
      );
    });

    test(
        'under virtual time, a timer a use case left pending fails the flow, '
        'naming it', () async {
      await expectLater(
        runJuiceFlow((flow) async {
          final c = flow.add(_Counter());
          await flow.send(c, _FireAndForget());
        }, virtualTime: true),
        _fails(allOf(contains('1 timer(s) still pending when the flow ended'),
            contains('0:00:00.020000'))),
      );
    });

    test(
        'under virtual time, an error a leftover timer would have thrown is '
        'not silently lost', () async {
      await expectLater(
        runJuiceFlow((flow) async {
          final c = flow.add(_Counter());
          await flow.send(c, _ThrowLater());
        }, virtualTime: true),
        _fails(contains('still pending when the flow ended')),
      );
    });
  });

  group('stuck under virtual time', () {
    test(
        'a sendAfter poll re-arming itself while the body waits on nothing is '
        'called stuck — at once, not at the runner\'s timeout', () async {
      final real = Stopwatch()..start();
      await expectLater(
        runJuiceFlow((flow) async {
          final c = flow.add(_Counter());
          unawaited(c.send(_Poll()));
          await Completer<void>().future; // parked on "the real world"
        }, virtualTime: true),
        _fails(allOf(
          contains('the blocs never went idle for an hour of virtual time'),
          contains('delayed send _Poll to _Counter'),
        )),
      );
      expect(real.elapsed, lessThan(const Duration(seconds: 10)));
      expect(JuiceActivityProbe.current, isNull);
    });
  });

  group('a flow that never ends', () {
    // The first test starts a flow whose body never completes and returns
    // without awaiting it — the shape a test that times out leaves behind.
    // Its teardown must hand the global state back.
    test('is abandoned at the end of its test', () async {
      unawaited(runJuiceFlow((flow) async {
        flow.add(_Counter());
        BlocScope.register<_Other>(() => _Other(),
            lifecycle: BlocLifecycle.permanent);
        await Completer<void>().future;
      }));
      await pump();
      expect(JuiceActivityProbe.current, isNotNull, reason: 'still running');
    });

    test('and the next test starts clean', () async {
      expect(JuiceActivityProbe.current, isNull);
      expect(BlocScope.hasRegistrations, isFalse);
      await runJuiceFlow((flow) async {
        final c = flow.add(_Counter());
        await flow.send(c, _Set(1));
        flow.expect(c, [isUpdatingStatus(state: const _S(1))]);
      });
    });
  });
}
