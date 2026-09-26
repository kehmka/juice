import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';
import 'package:juice/testing.dart';

/// juiceTest (1.9.0): declarative bloc tests — no sleeps, close before
/// assert, groups as widgets saw them, errors and late emissions reported.

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

class _Inc extends EventBase {}

class _TwoStep extends EventBase {}

class _Boom extends EventBase {}

class _Leaky extends EventBase {}

class _Slow extends EventBase {
  _Slow(this.gate);
  final Future<void> gate;
}

class _SlowUC extends BlocUseCase<_B, _Slow> {
  @override
  Future<void> execute(_Slow e) async {
    await e.gate;
    emitUpdate(newState: const _S(7));
  }
}

class _IncUC extends BlocUseCase<_B, _Inc> {
  @override
  Future<void> execute(_Inc e) async {
    emitWaiting(groupsToRebuild: {'count'});
    await Future<void>.delayed(const Duration(milliseconds: 5));
    emitUpdate(newState: _S(bloc.state.n + 1), groupsToRebuild: {'count'});
  }
}

class _TwoStepUC extends BlocUseCase<_B, _TwoStep> {
  @override
  Future<void> execute(_TwoStep e) async {
    emitUpdate(newState: const _S(10), groupsToRebuild: {'a'});
    emitUpdate(newState: const _S(20), groupsToRebuild: {'b'});
  }
}

class _BoomUC extends BlocUseCase<_B, _Boom> {
  @override
  Future<void> execute(_Boom e) async => throw StateError('boom');
}

class _LeakyUC extends BlocUseCase<_B, _Leaky> {
  @override
  Future<void> execute(_Leaky e) async {
    // Fire-and-forget work that outlives the event's processing.
    Future<void>.delayed(const Duration(milliseconds: 20),
        () => emitUpdate(newState: const _S(99)));
  }
}

class _B extends JuiceBloc<_S> {
  _B()
      : super(const _S(0), [
          () => UseCaseBuilder.typed(() => _IncUC(),
              concurrency: EventConcurrency.sequential),
          () => UseCaseBuilder.typed(() => _TwoStepUC(),
              concurrency: EventConcurrency.sequential),
          () => UseCaseBuilder.typed(() => _BoomUC(),
              concurrency: EventConcurrency.sequential),
          () => UseCaseBuilder.typed(() => _LeakyUC(),
              concurrency: EventConcurrency.sequential),
          () => UseCaseBuilder.typed(() => _SlowUC(),
              concurrency: EventConcurrency.sequential),
        ]);
}

void main() {
  juiceTest<_B, _S>(
    'records the status sequence with its groups — no sleeps',
    build: () => _B(),
    act: (b) => b.send(_Inc()),
    expect: () => [
      isWaitingStatus(groups: {'count'}),
      isUpdatingStatus(state: const _S(1), groups: {'count'}),
    ],
  );

  juiceTest<_B, _S>(
    'seed sets the start state and is not recorded',
    build: () => _B(),
    seed: () => const _S(41),
    act: (b) => b.send(_Inc()),
    skip: 1,
    expect: () => [isUpdatingStatus(state: const _S(42))],
  );

  juiceTest<_B, _S>(
    'groups are snapshotted per emission (gotcha 4)',
    build: () => _B(),
    act: (b) => b.send(_TwoStep()),
    expect: () => [
      isUpdatingStatus(state: const _S(10), groups: {'a'}),
      isUpdatingStatus(state: const _S(20), groups: {'a', 'b'}),
    ],
    verify: (b) {
      expect(b.isClosed, isTrue, reason: 'verify runs on the closed bloc');
    },
  );

  juiceTest<_B, _S>(
    'expected use-case errors are asserted with errors:',
    build: () => _B(),
    act: (b) => b.send(_Boom()),
    errors: () => [isStateError],
  );

  test('an unexpected use-case error fails the test', () async {
    await expectLater(
      runJuiceTest<_B, _S>(build: () => _B(), act: (b) => b.send(_Boom())),
      throwsA(isA<TestFailure>()),
    );
  });

  test('a wrong expectation fails with the emitted sequence', () async {
    await expectLater(
      runJuiceTest<_B, _S>(
        build: () => _B(),
        act: (b) => b.send(_Inc()),
        expect: () => [isUpdatingStatus()],
      ),
      throwsA(isA<TestFailure>()),
    );
  });

  test('a use case still running at close fails the test', () async {
    final gate = Completer<void>();
    await expectLater(
      runJuiceTest<_B, _S>(
        build: () => _B(),
        // Forgot to return the future: _Slow is still awaiting its gate.
        act: (b) {
          b.send(_Slow(gate.future));
        },
      ),
      throwsA(isA<TestFailure>()),
    );
    gate.complete();
  });

  test('allowInFlightAtClose opts out', () async {
    final gate = Completer<void>();
    await runJuiceTest<_B, _S>(
      build: () => _B(),
      act: (b) {
        b.send(_Slow(gate.future));
      },
      allowInFlightAtClose: true,
    );
    gate.complete();
  });

  test('wait: covers deliberate post-processing work', () async {
    final emissions = await runJuiceTest<_B, _S>(
      build: () => _B(),
      act: (b) => b.send(_Leaky()),
      wait: const Duration(milliseconds: 40),
    );
    expect(emissions.single.state, const _S(99));
  });
}
