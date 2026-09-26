import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';

/// Regressions for the core bugs the 1.9.0 coverage push surfaced (each fails
/// against 1.8.1 and passes now), plus one pin for BlocScope.endAll's leak
/// report.

class _S extends BlocState {
  const _S([this.n = 0]);
  final int n;
}

class _Order extends CancellableEvent {
  _Order(this.id);
  final String id;
}

class _Timed extends CancellableEvent with TimeoutSupport {
  _Timed(Duration d) {
    timeout = d;
  }
}

class _TimedUC extends BlocUseCase<_TimedBloc, _Timed> {
  @override
  Future<void> execute(_Timed e) async => emitUpdate(newState: const _S(1));
}

class _TimedBloc extends JuiceBloc<_S> {
  _TimedBloc()
      : super(const _S(), [
          () => UseCaseBuilder.typed(() => _TimedUC()),
        ]);
}

class _Leased extends JuiceBloc<_S> {
  _Leased() : super(const _S(), const []);
}

class _FailAndGo extends EventBase {}

class _InlineBloc extends JuiceBloc<_S> {
  _InlineBloc(this.navigations)
      : super(
          const _S(),
          [
            () => InlineUseCaseBuilder<_InlineBloc, _S, _FailAndGo>(
                  typeOfEvent: _FailAndGo,
                  handler: (ctx, e) async => ctx.emit.failure(
                    newState: const _S(2),
                    groups: {'f'},
                    aviatorName: 'go',
                  ),
                ),
          ],
          [
            () => Aviator(name: 'go', navigateWhere: (_) => navigations.add(1)),
          ],
        );
  final List<int> navigations;
}

void main() {
  group('CancellableEvent equality is identity', () {
    test('two different orders are not equal', () {
      expect(_Order('a') == _Order('b'), isFalse);
    });

    test('a cancelled event is still found in a Set', () {
      final e = _Order('a');
      final pending = {e};
      e.cancel();
      expect(pending.contains(e), isTrue,
          reason: 'hashCode used to change on cancel()');
    });
  });

  test('a TimeoutSupport timer stops when its use case finishes', () async {
    final b = _TimedBloc();
    final e = _Timed(const Duration(milliseconds: 20));
    await b.send(e);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(e.isTimedOut, isFalse,
        reason: 'the completed event was later marked timed out');
    expect(e.isCancelled, isFalse);
    await b.close();
  });

  test('BlocScope.endAll reports an unreleased lease', () async {
    BlocScope.reset();
    addTearDown(BlocScope.reset);
    final printed = <String>[];
    final original = debugPrint;
    debugPrint = (String? m, {int? wrapWidth}) => printed.add(m ?? '');
    addTearDown(() => debugPrint = original);

    BlocScope.register<_Leased>(() => _Leased(),
        lifecycle: BlocLifecycle.leased);
    BlocScope.lease<_Leased>(); // never released
    await BlocScope.endAll();

    // A pin, not a regression: 1.8.1 reported this too. The check now
    // explicitly runs before the closes that zero the counts.
    expect(printed.join('\n'), contains('unreleased leases'));
  });

  test('inline navigation does not emit an extra UpdatingStatus', () async {
    final navigations = <int>[];
    final b = _InlineBloc(navigations);
    final statuses = <StreamStatus<_S>>[];
    final sub = b.stream.listen(statuses.add);
    await b.send(_FailAndGo());
    await Future<void>.delayed(Duration.zero);

    expect(navigations, [1]);
    expect(statuses.map((s) => s.runtimeType.toString()),
        [contains('FailureStatus')],
        reason: 'was [Failure, Updating]: the failure got overwritten');
    expect(statuses.single.event?.groupsToRebuild, {'f'},
        reason: 'was {f, *}: every widget rebuilt');
    await sub.cancel();
    await b.close();
  });
}
