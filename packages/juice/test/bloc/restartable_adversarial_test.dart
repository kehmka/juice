import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';

/// The adversarial review of `restartable` (2026-10-13): the cases a
/// first-pass test suite does not think of. Each test states the contract it
/// pins.
///
/// 1. The fence is per RUN, not per event object: re-sending the same event
///    instance supersedes the first run and fences it.
/// 2. The run's zone does NOT leak into nested dispatches: a different event
///    sent from inside a restartable run keeps its own identity — its
///    bindings are not the outer run's, `isSuperseded` is its own, its span
///    is not flagged when the outer run is superseded.
/// 3. A sequential event queued from inside a restartable run is likewise
///    its own.
/// 4. A callback scheduled by the run (Timer / Future.delayed) IS the run:
///    a binding it creates belongs to the run (zone semantics, documented).
/// 5. sendAndWait: an event that emitted and is THEN superseded answers
///    with its emission, not a CancelingStatus.
/// 6. Stress: many rapid events, completed in reverse, leave exactly one
///    emission and no live bindings.
/// 7. close() mid-run cancels the run's bindings; nothing emits after.

class _S extends BlocState {
  const _S(this.log);
  final List<String> log;
}

class _Outer extends EventBase {
  _Outer(this.gate, {this.nested, this.scheduleBinding = false});
  final Future<void> gate;
  final EventBase? nested; // sent from inside the run, before the gate
  final bool scheduleBinding;
}

class _Inner extends EventBase {
  _Inner(this.gate);
  final Future<void> gate;
}

class _Seq extends EventBase {
  _Seq(this.gate);
  final Future<void> gate;
}

class _OuterUC extends BlocUseCase<_B, _Outer> {
  @override
  Future<void> execute(_Outer e) async {
    if (e.nested != null) bloc.send(e.nested!); // NOT awaited: stays in flight
    if (e.scheduleBinding) {
      // A callback the run scheduled: it runs in the run's zone.
      Future<void>.delayed(Duration.zero, () {
        bloc.bindStream<int>(bloc.scheduled.stream, (_) {});
      });
    }
    await e.gate;
    bloc.outerSawSuperseded.add(isSuperseded);
    if (isSuperseded) return;
    emitUpdate(
        newState: _S([...bloc.state.log, 'outer']), groupsToRebuild: {'g'});
  }
}

class _InnerUC extends BlocUseCase<_B, _Inner> {
  @override
  Future<void> execute(_Inner e) async {
    bloc.bindStream<int>(bloc.innerSource.stream, (_) {}, key: 'inner');
    await e.gate;
    bloc.innerSawSuperseded.add(isSuperseded);
    emitUpdate(
        newState: _S([...bloc.state.log, 'inner']), groupsToRebuild: {'g'});
  }
}

class _SeqUC extends BlocUseCase<_B, _Seq> {
  @override
  Future<void> execute(_Seq e) async {
    await e.gate;
    bloc.seqSawSuperseded.add(isSuperseded);
    emitUpdate(
        newState: _S([...bloc.state.log, 'seq']), groupsToRebuild: {'g'});
  }
}

class _B extends JuiceBloc<_S> {
  _B(JuiceLogger log)
      : super(
          const _S([]),
          [
            () => UseCaseBuilder.typed(() => _OuterUC(),
                concurrency: EventConcurrency.restartable),
            () => UseCaseBuilder.typed(() => _InnerUC(),
                concurrency: EventConcurrency.concurrent),
            () => UseCaseBuilder.typed(() => _SeqUC(),
                concurrency: EventConcurrency.sequential),
          ],
          const [],
          log,
        );
  final innerSource = StreamController<int>.broadcast();
  final scheduled = StreamController<int>.broadcast();
  final outerSawSuperseded = <bool>[];
  final innerSawSuperseded = <bool>[];
  final seqSawSuperseded = <bool>[];
  @override
  Future<void> close() async {
    await innerSource.close();
    await scheduled.close();
    await super.close();
  }
}

class _Log implements JuiceLogger {
  final entries = <Map<String, dynamic>>[];
  @override
  void log(String m,
          {Level level = Level.info, Map<String, dynamic>? context}) =>
      entries.add({'message': m, ...?context});
  @override
  void logError(String m, Object e, StackTrace s,
          {Map<String, dynamic>? context}) =>
      entries.add({'message': m, 'error': e, ...?context});
  Iterable<Map<String, dynamic>> typed(String t) =>
      entries.where((e) => e['type'] == t);
}

Future<void> pump([int n = 2]) async {
  for (var i = 0; i < n; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late JuiceLogger saved;
  setUp(() => saved = JuiceLoggerConfig.logger);
  tearDown(() => JuiceLoggerConfig.configureLogger(saved));

  test(
      '1. the same event INSTANCE sent twice: the first run is superseded '
      'and fenced, the second emits once', () async {
    final b = _B(_Log());
    final gate = Completer<void>();
    final e = _Outer(gate.future);
    final first = b.send(e);
    final second = b.send(e);
    gate.complete();
    await Future.wait([first, second]);
    expect(b.state.log, ['outer'], reason: 'exactly one emission');
    expect(b.outerSawSuperseded, [true, false]);
    await b.close();
  });

  test(
      '2. a nested dispatch from inside a restartable run is its own: its '
      'binding survives the outer supersede, it is not "superseded", its '
      'span is not flagged', () async {
    final log = _Log();
    JuiceLoggerConfig.configureLogger(log);
    final b = _B(log);
    final innerGate = Completer<void>();
    final outerGate = Completer<void>();
    final outer1 =
        b.send(_Outer(outerGate.future, nested: _Inner(innerGate.future)));
    await pump();
    expect(b.activeBindingCount, 1, reason: 'the inner binding exists');
    final outer2 =
        b.send(_Outer(Completer<void>().future)); // supersedes outer1
    await pump();
    expect(b.activeBindingCount, 1,
        reason: 'the INNER run created the binding, not the superseded outer');
    innerGate.complete();
    await pump();
    expect(b.innerSawSuperseded, [false], reason: 'inner is not superseded');
    expect(b.state.log, contains('inner'));
    final innerEnd = log
        .typed('use_case_completed')
        .firstWhere((e) => e['event'] == '_Inner');
    expect(innerEnd.containsKey('superseded'), isFalse,
        reason: 'the inner span is not the superseded one');
    outerGate.complete();
    await outer1;
    b.unbind('inner');
    await b.close();
    outer2.ignore();
  });

  test('3. a sequential event queued from inside a restartable run is its own',
      () async {
    final b = _B(_Log());
    final seqGate = Completer<void>();
    final outerGate = Completer<void>();
    final outer1 =
        b.send(_Outer(outerGate.future, nested: _Seq(seqGate.future)));
    await pump();
    final outer2 = b.send(_Outer(Completer<void>().future));
    await pump();
    seqGate.complete();
    await pump();
    expect(b.seqSawSuperseded, [false]);
    expect(b.state.log, contains('seq'));
    outerGate.complete();
    await outer1;
    await b.close();
    outer2.ignore();
  });

  test(
      '4. a binding created by a callback the run scheduled belongs to the '
      'run and is cancelled with it (zone semantics)', () async {
    final b = _B(_Log());
    final gate = Completer<void>();
    final run1 = b.send(_Outer(gate.future, scheduleBinding: true));
    await pump(3);
    expect(b.activeBindingCount, 1);
    final run2 = b.send(_Outer(Completer<void>().future));
    await pump();
    expect(b.activeBindingCount, 0,
        reason: 'the scheduled binding was the run\'s');
    gate.complete();
    await run1;
    await b.close();
    run2.ignore();
  });

  test(
      '5. sendAndWait: an event that emitted and is THEN superseded answers '
      'with its emission', () async {
    final b = _B(_Log());
    final w = b.sendAndWait(_Outer(Future.value()));
    final status = await w;
    expect(status, isA<UpdatingStatus<_S>>());
    b.send(
        _Outer(Completer<void>().future)); // supersedes a finished run: no-op
    await pump();
    expect(b.state.log, ['outer']);
    await b.close();
  });

  test(
      '6. stress: 50 rapid events completed in reverse leave one emission '
      'and no live bindings', () async {
    final b = _B(_Log());
    final gates = [for (var i = 0; i < 50; i++) Completer<void>()];
    final sends = [
      for (final g in gates) b.send(_Outer(g.future, scheduleBinding: true))
    ];
    await pump(3);
    for (final g in gates.reversed) {
      g.complete();
    }
    await Future.wait(sends);
    expect(b.state.log, ['outer']);
    expect(b.outerSawSuperseded.where((s) => !s).length, 1);
    expect(b.activeBindingCount, 1, reason: 'only the winner\'s binding lives');
    await b.close();
    expect(b.activeBindingCount, 0);
  });

  fenceMain();

  test('7. close() mid-run cancels the run\'s bindings and nothing emits after',
      () async {
    final b = _B(_Log());
    final gate = Completer<void>();
    final run = b.send(_Outer(gate.future, scheduleBinding: true));
    await pump(3);
    expect(b.activeBindingCount, 1);
    await b.close();
    expect(b.activeBindingCount, 0);
    gate.complete();
    await run;
    expect(b.state.log, isEmpty);
  });
}

// ---- added after the first run of the review: the two cases above passed
// for the wrong reason (the use case cooperated), so pin the FENCE itself.

class _Blind extends EventBase {
  _Blind(this.gate);
  final Future<void> gate;
}

/// Does NOT check isSuperseded: only the fence can stop its emission.
class _BlindUC extends BlocUseCase<_BlindBloc, _Blind> {
  @override
  Future<void> execute(_Blind e) async {
    await e.gate;
    emitUpdate(
        newState: _S([...bloc.state.log, 'blind']), groupsToRebuild: {'g'});
  }
}

class _Bind extends EventBase {
  _Bind(this.gate);
  final Future<void> gate;
}

/// Binds a stream only AFTER its gate — by then it may be superseded.
class _BindUC extends BlocUseCase<_BlindBloc, _Bind> {
  @override
  Future<void> execute(_Bind e) async {
    await e.gate;
    final b = bloc.bindStream<int>(bloc.src.stream, (_) {});
    bloc.lateBindings.add(b);
  }
}

class _BlindBloc extends JuiceBloc<_S> {
  _BlindBloc(JuiceLogger log)
      : super(
          const _S([]),
          [
            () => UseCaseBuilder.typed(() => _BlindUC(),
                concurrency: EventConcurrency.restartable),
            () => UseCaseBuilder.typed(() => _BindUC(),
                concurrency: EventConcurrency.restartable),
          ],
          const [],
          log,
        );
  final src = StreamController<int>.broadcast();
  final lateBindings = <StreamBinding<int>>[];
  @override
  Future<void> close() async {
    await src.close();
    await super.close();
  }
}

void fenceMain() {
  test(
      '1b. the FENCE, not cooperation: the same instance sent twice, the '
      'use case never checks isSuperseded — the first run\'s emit is dropped',
      () async {
    final log = _Log();
    final b = _BlindBloc(log);
    final gate = Completer<void>();
    final e = _Blind(gate.future);
    final first = b.send(e);
    final second = b.send(e);
    gate.complete();
    await Future.wait([first, second]);
    expect(b.state.log, ['blind'],
        reason: 'one emission: the first was fenced');
    expect(log.typed('state_emission_superseded'), hasLength(1));
    await b.close();
  });

  test(
      '8. a run that binds a stream AFTER it was superseded gets an inert '
      'binding, logged — no orphan outlives the fence', () async {
    final log = _Log();
    final b = _BlindBloc(log);
    final gate = Completer<void>();
    final first = b.send(_Bind(gate.future));
    final second = b.send(_Bind(Completer<void>().future)); // supersedes first
    gate.complete();
    await first;
    expect(b.lateBindings.single.isActive, isFalse);
    expect(b.activeBindingCount, 0);
    expect(
        log.typed('stream_binding').where((e) => e['action'] == 'superseded'),
        hasLength(1));
    await b.close();
    second.ignore();
  });
}
