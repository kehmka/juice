import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';
import 'package:juice/src/bloc/src/core/activity_probe.dart';
import '../support/capture_logger.dart';

/// The activity probe: what the framework tells a test flow so it knows
/// when every bloc is idle. A send is in flight from the call until its
/// processing is over; a reaction hop from the emission that decided it
/// until its event is sent or dropped. Outside a flow there is no probe and
/// nothing is reported.

class _S extends BlocState {
  const _S(this.n);
  final int n;
}

class _Set extends EventBase {
  _Set(this.n);
  final int n;
}

class _Slow extends EventBase {
  _Slow(this.n);
  final int n;
}

class _Once extends EventBase {
  _Once(this.gate);
  final Future<void> gate;
}

class _Boom extends EventBase {}

class _Unknown extends EventBase {}

class _SetUC extends BlocUseCase<_Bloc, _Set> {
  @override
  Future<void> execute(_Set e) async => emitUpdate(newState: _S(e.n));
}

class _SlowUC extends BlocUseCase<_Bloc, _Slow> {
  @override
  Future<void> execute(_Slow e) async {
    await Future<void>.delayed(const Duration(milliseconds: 5));
    emitUpdate(newState: _S(e.n));
  }
}

class _OnceUC extends BlocUseCase<_Bloc, _Once> {
  @override
  Future<void> execute(_Once e) async {
    await e.gate;
    emitUpdate(newState: const _S(1));
  }
}

class _BoomUC extends BlocUseCase<_Bloc, _Boom> {
  @override
  Future<void> execute(_Boom e) async => throw StateError('boom');
}

class _Bloc extends JuiceBloc<_S> {
  _Bloc()
      : super(
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
                typeOfEvent: _Once,
                useCaseGenerator: () => _OnceUC(),
                concurrency: EventConcurrency.droppable),
            () => UseCaseBuilder(
                typeOfEvent: _Boom,
                useCaseGenerator: () => _BoomUC(),
                concurrency: EventConcurrency.concurrent),
          ],
          const [],
          CaptureLogger(),
        );
}

class _Src extends _Bloc {}

class _Dst extends _Bloc {}

/// Writes down everything it is told, and how much was in flight after
/// each call.
class _Probe implements JuiceActivityProbe {
  final log = <String>[];
  final inFlight = <JuiceWork>{};
  final sizes = <int>[];

  @override
  void began(JuiceWork work) {
    inFlight.add(work);
    log.add('began $work');
    sizes.add(inFlight.length);
  }

  @override
  void ended(JuiceWork work) {
    expect(inFlight.remove(work), isTrue, reason: '$work ended twice');
    log.add('ended $work');
    sizes.add(inFlight.length);
  }
}

Future<void> _turn() => Future<void>.delayed(Duration.zero);

void main() {
  late _Probe probe;

  setUp(() {
    probe = _Probe();
    JuiceActivityProbe.current = probe;
  });

  tearDown(() => JuiceActivityProbe.current = null);

  test('work describes itself', () {
    expect(JuiceWork.send('CartBloc', 'AddItem').toString(),
        'send AddItem to CartBloc');
    expect(JuiceWork.hop('AuthBloc', 'CartBloc').toString(),
        'hop AuthBloc → CartBloc');
  });

  test('a send is in flight from the call until its processing is over',
      () async {
    final bloc = _Bloc();
    addTearDown(bloc.close);

    final sent = bloc.send(_Slow(1));
    expect(probe.log, ['began send _Slow to _Bloc']);

    await sent;
    expect(bloc.state.n, 1);
    expect(
        probe.log, ['began send _Slow to _Bloc', 'ended send _Slow to _Bloc']);
  });

  test('a queued sequential event is in flight while it waits', () async {
    final bloc = _Bloc();
    addTearDown(bloc.close);

    final first = bloc.send(_Slow(1));
    final second = bloc.send(_Slow(2));
    expect(probe.inFlight, hasLength(2));

    await first;
    expect(bloc.state.n, 1);
    expect(probe.inFlight, hasLength(1),
        reason: 'the second has not run yet, and is still counted');

    await second;
    expect(probe.inFlight, isEmpty);
  });

  test('a dropped event, a failed run and an unhandled event all end',
      () async {
    final bloc = _Bloc();
    addTearDown(bloc.close);
    final gate = Completer<void>();

    final running = bloc.send(_Once(gate.future));
    await bloc.send(_Once(gate.future)); // dropped
    expect(probe.inFlight, hasLength(1));

    await bloc.send(_Boom());
    await bloc.send(_Unknown());
    expect(probe.inFlight, hasLength(1));

    gate.complete();
    await running;
    expect(probe.inFlight, isEmpty);
    expect(probe.log.where((l) => l.startsWith('began')), hasLength(4));
  });

  test('a send to a closed bloc is ignored, and is not work', () async {
    final bloc = _Bloc();
    await bloc.close();
    await bloc.send(_Set(1));
    expect(probe.log, isEmpty);
  });

  test(
      'a reaction: the hop is in flight from the emission that decided it '
      'until its event is sent — the chain is never idle in between', () async {
    final src = _Src();
    final dst = _Dst();
    addTearDown(src.close);
    addTearDown(dst.close);
    dst.react(Reaction<_Src, _S>.changes((s) => s.n,
        source: src, send: (s) => _Slow(s.n), atAttach: AtAttach.skip));

    src.send(_Set(4));
    // The use case ran synchronously up to its emit: the hop is decided.
    expect(probe.log, ['began send _Set to _Src', 'began hop _Src → _Dst']);

    await _turn();
    await dst.waitFor((s) => s.n == 4, timeout: const Duration(seconds: 2));
    await _turn();

    expect(probe.inFlight, isEmpty);
    expect(
        probe.log,
        containsAllInOrder(<String>[
          'began hop _Src → _Dst',
          'began send _Slow to _Dst',
          'ended hop _Src → _Dst',
          'ended send _Slow to _Dst',
        ]));
    // Idle exactly once: at the very end.
    expect(probe.sizes.where((size) => size == 0), hasLength(1));
    expect(probe.sizes.last, 0);
  });

  test('a catch-up hop at attach is work', () async {
    final src = _Src();
    final dst = _Dst();
    addTearDown(src.close);
    addTearDown(dst.close);
    await src.send(_Set(2));
    probe.log.clear();

    dst.react(Reaction<_Src, _S>.changes((s) => s.n,
        source: src, send: (s) => _Set(s.n), atAttach: AtAttach.catchUp));
    expect(probe.log, ['began hop _Src → _Dst']);

    await _turn();
    expect(dst.state.n, 2);
    expect(probe.inFlight, isEmpty);
  });

  test('a hop that is dropped or fails still ends', () async {
    final src = _Src();
    final cancelled = _Dst();
    final broken = _Dst();
    addTearDown(src.close);
    addTearDown(cancelled.close);
    addTearDown(broken.close);
    final binding = cancelled.react(Reaction<_Src, _S>.changes((s) => s.n,
        source: src, send: (s) => _Set(s.n), atAttach: AtAttach.skip));
    broken.react(Reaction<_Src, _S>.changes((s) => s.n,
        source: src,
        send: (_) => throw StateError('send broke'),
        atAttach: AtAttach.skip));

    final sent = src.send(_Set(1));
    expect(probe.log.where((l) => l.startsWith('began hop')), hasLength(2));
    binding.cancel(); // between the emission and the microtask
    await sent;
    await _turn();

    expect(probe.inFlight, isEmpty);
    expect(probe.log.where((l) => l.startsWith('ended hop')), hasLength(2));
    expect(probe.log.where((l) => l.contains('to _Dst')), isEmpty,
        reason: 'neither hop sent anything');
    expect(cancelled.state.n, 0);
  });

  test('outside a flow nothing is reported', () async {
    JuiceActivityProbe.current = null;
    final src = _Src();
    final dst = _Dst();
    addTearDown(src.close);
    addTearDown(dst.close);
    dst.react(Reaction<_Src, _S>.changes((s) => s.n,
        source: src, send: (s) => _Set(s.n), atAttach: AtAttach.skip));

    await src.send(_Set(3));
    await _turn();

    expect(dst.state.n, 3);
    expect(probe.log, isEmpty);
  });

  test(
      'work that began under a probe ends on that probe, even after it is '
      'taken away', () async {
    final bloc = _Bloc();
    addTearDown(bloc.close);

    final sent = bloc.send(_Slow(1));
    JuiceActivityProbe.current = null;
    await sent;

    expect(
        probe.log, ['began send _Slow to _Bloc', 'ended send _Slow to _Bloc']);
  });
}
