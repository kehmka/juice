import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';

/// UseCaseBuilder.typed (1.9.0): the event type is inferred from the use
/// case (a mismatch is a compile error, not a dispatch-time cast failure),
/// and the bloc type is checked when the bloc registers the builder.

class _S extends BlocState {
  const _S(this.n);
  final int n;
}

class _Load extends EventBase {}

class _Save extends EventBase {
  _Save(this.n);
  final int n;
}

class _LoadUC extends BlocUseCase<_B, _Load> {
  @override
  Future<void> execute(_Load e) async => emitUpdate(newState: const _S(1));
}

class _SaveUC extends BlocUseCase<_B, _Save> {
  static int running = 0, maxRunning = 0;
  @override
  Future<void> execute(_Save e) async {
    running++;
    if (running > maxRunning) maxRunning = running;
    await Future<void>.delayed(const Duration(milliseconds: 5));
    emitUpdate(newState: _S(bloc.state.n + e.n));
    running--;
  }
}

class _B extends JuiceBloc<_S> {
  _B()
      : super(const _S(0), [
          () => UseCaseBuilder.typed(() => _LoadUC()),
          () => UseCaseBuilder.typed(() => _SaveUC(),
              concurrency: EventConcurrency.sequential),
        ]);
}

class _Wrong extends JuiceBloc<_S> {
  _Wrong()
      : super(const _S(0), [
          () => UseCaseBuilder.typed(() => _LoadUC()), // _LoadUC is for _B
        ]);
}

class _Seeded extends JuiceBloc<_S> {
  _Seeded()
      : super(const _S(0), [
          () => UseCaseBuilder.typed(() => _SeedUC(),
              initialEventBuilder: () => _Seed()),
        ]);
}

class _Seed extends EventBase {}

class _SeedUC extends BlocUseCase<_Seeded, _Seed> {
  @override
  Future<void> execute(_Seed e) async => emitUpdate(newState: const _S(42));
}

void main() {
  test('the event type is inferred from the use case', () async {
    final b = _B();
    await b.send(_Load());
    expect(b.state.n, 1);
    await b.close();
  });

  test('concurrency passes through', () async {
    _SaveUC.maxRunning = 0;
    final b = _B();
    await Future.wait([b.send(_Save(1)), b.send(_Save(2)), b.send(_Save(3))]);
    expect(_SaveUC.maxRunning, 1, reason: 'sequential: one at a time');
    expect(b.state.n, 6);
    await b.close();
  });

  test('initialEventBuilder passes through', () async {
    final b = _Seeded();
    await Future<void>.delayed(Duration.zero);
    expect(b.state.n, 42);
    await b.close();
  });

  test('registering on the wrong bloc fails at construction, naming both', () {
    expect(
      () => _Wrong(),
      throwsA(isA<ArgumentError>().having((e) => '${e.message}', 'message',
          allOf(contains('_Load'), contains('_B'), contains('_Wrong')))),
    );
  });

  test('the plain constructor is unchanged (no registration check)', () async {
    final builder =
        UseCaseBuilder(typeOfEvent: _Load, useCaseGenerator: () => _LoadUC());
    expect(builder.eventType, _Load);
    expect(() => builder.checkRegisteredOn(_B()), returnsNormally);
  });
}
