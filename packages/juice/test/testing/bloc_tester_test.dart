import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';
import 'package:juice/testing.dart';

/// BlocTester had no tests of its own; it now counts toward the core
/// coverage gate (juiceTest is the preferred API, BlocTester remains).

class _S extends BlocState {
  const _S(this.n);
  final int n;
}

class _Inc extends EventBase {}

class _Fail extends EventBase {}

class _IncUC extends BlocUseCase<_B, _Inc> {
  @override
  Future<void> execute(_Inc e) async {
    emitWaiting();
    emitUpdate(newState: _S(bloc.state.n + 1));
  }
}

class _FailUC extends BlocUseCase<_B, _Fail> {
  @override
  Future<void> execute(_Fail e) async => emitFailure(error: 'x');
}

class _B extends JuiceBloc<_S> {
  _B()
      : super(const _S(0), [
          () => UseCaseBuilder.typed(() => _IncUC(),
              concurrency: EventConcurrency.sequential),
          () => UseCaseBuilder.typed(() => _FailUC(),
              concurrency: EventConcurrency.sequential),
        ]);
}

void main() {
  test('records emissions and asserts on state and status', () async {
    final t = BlocTester<_B, _S>(_B());
    expect(t.lastStatus, isNull);
    expect(t.lastState.n, 0);

    await t.send(_Inc());
    expect(t.state.n, 1);
    expect(t.lastState.n, 1);
    t.expectState((s) => s.n == 1);
    t.expectLastStatusIs<UpdatingStatus>();
    t.expectStatusSequence([WaitingStatus, UpdatingStatus]);
    t.expectEmissionCount(2);
    t.expectWasWaiting();
    t.expectNoFailure();
    t.expectAnyEmission((s) => s is WaitingStatus);
    t.expectAllEmissions((s) => s.state.n <= 1);
    expect(t.emissions, hasLength(2));

    t.clearEmissions();
    await t.send(_Fail(), delay: Duration.zero);
    t.expectWasFailure();
    t.expectStatusSequence([FailureStatus]);
    await t.dispose();
  });

  test('sendAndWaitForResult returns the first non-waiting status', () async {
    final t = _B().tester();
    final status = await t.sendAndWaitForResult(_Inc());
    expect(status, isA<UpdatingStatus>());
    await t.dispose();
  });

  test('waitForEmissions waits, and times out when nothing comes', () async {
    final t = BlocTester<_B, _S>(_B());
    final waiting = t.waitForEmissions(2);
    t.bloc.send(_Inc());
    await waiting;
    expect(t.emissions.length, greaterThanOrEqualTo(2));
    await expectLater(
      t.waitForEmissions(1, timeout: const Duration(milliseconds: 20)),
      throwsA(isA<TimeoutException>()),
    );
    await t.dispose();
  });

  test('expectStatusSequence with skip, and exact-type fallback', () async {
    final t = BlocTester<_B, _S>(_B());
    await t.send(_Inc());
    t.expectStatusSequence([UpdatingStatus], skip: 1);
    await t.dispose();
  });
}
