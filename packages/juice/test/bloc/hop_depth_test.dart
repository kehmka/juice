// ignore_for_file: implementation_imports
import 'package:flutter_test/flutter_test.dart' hide EventDispatcher;
import 'package:juice/juice.dart';
import 'package:juice/src/bloc/src/core/event_dispatcher.dart';

/// 2.0.0 collapsed the send path from four awaited hops to the executor's
/// one: `send`, `dispatch` and the mode wrappers return futures through.
/// These pins hold the contracts that `async` used to give for free.

class _S extends BlocState {
  const _S(this.n);
  final int n;
}

class _E extends EventBase {
  _E([this.fail = false]);
  final bool fail;
}

class _Drop extends EventBase {
  _Drop(this.gate, {this.fail = false});
  final Future<void> gate;
  final bool fail;
}

class _Unknown extends EventBase {}

class _UC extends BlocUseCase<_B, _E> {
  @override
  Future<void> execute(_E e) async {
    if (e.fail) throw StateError('use case failed');
    emitUpdate(newState: _S(bloc.state.n + 1), groupsToRebuild: {'g'});
  }
}

class _DropUC extends BlocUseCase<_B, _Drop> {
  @override
  Future<void> execute(_Drop e) async {
    await e.gate;
    if (e.fail) throw StateError('dropped run failed');
    emitUpdate(newState: _S(bloc.state.n + 10), groupsToRebuild: {'g'});
  }
}

class _B extends JuiceBloc<_S> {
  _B(JuiceLogger log)
      : super(
          const _S(0),
          [
            () => UseCaseBuilder.typed(() => _UC(),
                concurrency: EventConcurrency.sequential),
            () => UseCaseBuilder.typed(() => _DropUC(),
                concurrency: EventConcurrency.droppable),
          ],
          const [],
          log,
          BlocErrorHandler(onError: (m, {error, stackTrace}) {}),
        );
}

class _Log implements JuiceLogger {
  @override
  void record(JuiceTelemetry e) =>
      types.add(e.isError ? 'ERR:${e.kind.wireType}' : e.kind.wireType);

  final types = <String>[];
  @override
  void log(String m,
          {Level level = Level.info, Map<String, dynamic>? context}) =>
      types.add(context?['type'] as String? ?? '(untyped)');
  @override
  void logError(String m, Object e, StackTrace s,
          {Map<String, dynamic>? context}) =>
      types.add('ERR:${context?['type']}');
}

void main() {
  test(
      'an un-awaited send of an unhandled event does not throw into the '
      'caller: the error arrives on the future', () async {
    final d = EventDispatcher<EventBase>();
    late Future<void> f;
    expect(() => f = d.dispatch(_Unknown()), returnsNormally);
    await expectLater(f, throwsA(isA<StateError>()));
  });

  test('send on a closed bloc returns a completed future, no throw', () async {
    final b = _B(_Log());
    await b.close();
    late Future<void> f;
    expect(() => f = b.send(_E()), returnsNormally);
    await f;
  });

  test('sequential keeps order and continues past a failed run', () async {
    final b = _B(_Log());
    final sends = [b.send(_E()), b.send(_E(true)), b.send(_E())];
    await Future.wait(sends);
    expect(b.state.n, 2, reason: 'two succeeded, in order, around the failure');
    await b.close();
  });

  test('droppable frees the slot after a failed run and after a dropped one',
      () async {
    final b = _B(_Log());
    final gate = Completer<void>();
    final first = b.send(_Drop(gate.future, fail: true));
    await b.send(_Drop(Future.value())); // dropped: one in flight
    expect(b.state.n, 0);
    gate.complete();
    await first; // failed, swallowed by the executor
    await b.send(_Drop(Future.value())); // slot is free again
    expect(b.state.n, 10);
    await b.close();
  });

  test('the telemetry span still closes on success and on error', () async {
    final log = _Log();
    JuiceLoggerConfig.configureLogger(log);
    final b = _B(log);
    await b.send(_E());
    await b.send(_E(true));
    expect(log.types.where((t) => t == 'use_case_execution').length, 2);
    expect(log.types.where((t) => t == 'use_case_completed').length, 1);
    expect(log.types.where((t) => t == 'ERR:use_case_error').length,
        greaterThanOrEqualTo(1));
    await b.close();
  });
}
