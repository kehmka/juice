import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';
import '../support/capture_logger.dart';

/// What a trace can pair (bloc-to-bloc plan, step 2):
///
/// - every status a use case run emits carries that run's `executionId` on
///   its telemetry entry — `state_emission` and its skipped, superseded and
///   after-close variants — so an emission pairs with its `use_case_execution`
///   span even when two events of one type overlap;
/// - an event a `droppable` builder drops is recorded (`event_dropped`); it
///   was silent before.

class _S extends BlocState {
  const _S(this.tag);
  final String tag;

  @override
  bool operator ==(Object other) => other is _S && other.tag == tag;

  @override
  int get hashCode => tag.hashCode;
}

/// Emits `waiting`, then (after [gate]) its [tag] as an update.
class _Work extends EventBase {
  _Work(this.tag, this.gate);
  final String tag;
  final Future<void> gate;
}

class _FailNow extends EventBase {}

class _CancelNow extends EventBase {}

/// `emitUpdate(skipIfSame: true)` with the state it already has.
class _Same extends EventBase {}

/// Emits a status and re-emits an event AFTER the bloc closed.
class _Late extends EventBase {
  _Late(this.gate);
  final Future<void> gate;
}

class _Search extends EventBase {
  _Search(this.gate);
  final Future<void> gate;
}

class _Load extends EventBase {
  _Load(this.gate);
  final Future<void> gate;
}

class _Seq extends EventBase {
  _Seq(this.gate);
  final Future<void> gate;
}

class _Inline extends EventBase {}

/// A restartable run that is NOT superseded and emits every status kind.
class _AllKinds extends EventBase {}

class _AllKindsUC extends BlocUseCase<_B, _AllKinds> {
  @override
  Future<void> execute(_AllKinds e) async {
    emitWaiting();
    emitFailure(error: StateError('boom'));
    emitCancel();
    emitUpdate(newState: const _S('all'));
    emitUpdate(newState: const _S('all'), skipIfSame: true);
  }
}

class _WorkUC extends BlocUseCase<_B, _Work> {
  @override
  Future<void> execute(_Work e) async {
    emitWaiting();
    await e.gate;
    emitUpdate(newState: _S(e.tag));
  }
}

class _FailNowUC extends BlocUseCase<_B, _FailNow> {
  @override
  Future<void> execute(_FailNow e) async =>
      emitFailure(error: StateError('boom'));
}

class _CancelNowUC extends BlocUseCase<_B, _CancelNow> {
  @override
  Future<void> execute(_CancelNow e) async => emitCancel();
}

class _SameUC extends BlocUseCase<_B, _Same> {
  @override
  Future<void> execute(_Same e) async =>
      emitUpdate(newState: _S(bloc.state.tag), skipIfSame: true);
}

class _LateUC extends BlocUseCase<_B, _Late> {
  @override
  Future<void> execute(_Late e) async {
    await e.gate;
    emitUpdate(newState: const _S('late'));
    emitEvent(event: _Inline());
  }
}

class _SearchUC extends BlocUseCase<_B, _Search> {
  @override
  Future<void> execute(_Search e) async {
    await e.gate;
    emitUpdate(newState: const _S('found'));
  }
}

class _LoadUC extends BlocUseCase<_B, _Load> {
  @override
  Future<void> execute(_Load e) async {
    await e.gate;
    emitUpdate(newState: const _S('loaded'));
  }
}

class _SeqUC extends BlocUseCase<_B, _Seq> {
  @override
  Future<void> execute(_Seq e) async {
    await e.gate;
    emitUpdate(newState: const _S('seq'));
  }
}

class _B extends JuiceBloc<_S> {
  _B({JuiceLogger? logger})
      : super(
          const _S('initial'),
          [
            () => UseCaseBuilder.typed(() => _WorkUC(),
                concurrency: EventConcurrency.concurrent),
            () => UseCaseBuilder.typed(() => _FailNowUC(),
                concurrency: EventConcurrency.sequential),
            () => UseCaseBuilder.typed(() => _CancelNowUC(),
                concurrency: EventConcurrency.sequential),
            () => UseCaseBuilder.typed(() => _SameUC(),
                concurrency: EventConcurrency.sequential),
            () => UseCaseBuilder.typed(() => _LateUC(),
                concurrency: EventConcurrency.concurrent),
            () => UseCaseBuilder.typed(() => _SearchUC(),
                concurrency: EventConcurrency.restartable),
            () => UseCaseBuilder.typed(() => _LoadUC(),
                concurrency: EventConcurrency.droppable),
            () => UseCaseBuilder.typed(() => _AllKindsUC(),
                concurrency: EventConcurrency.restartable),
            () => UseCaseBuilder.typed(() => _SeqUC(),
                concurrency: EventConcurrency.sequential),
            () => InlineUseCaseBuilder<_B, _S, _Inline>(
                  typeOfEvent: _Inline,
                  concurrency: EventConcurrency.sequential,
                  handler: (ctx, e) async =>
                      ctx.emit.update(newState: const _S('inline')),
                ),
          ],
          const [],
          logger,
          quietErrorHandler,
        );
}

/// The `executionId` on the `use_case_execution` entry of each [event]-typed
/// run, in start order.
List<int> _spanIds(CaptureLogger log, String event) => [
      for (final e in log.typed('use_case_execution'))
        if (e['event'] == event) e['executionId'] as int,
    ];

void main() {
  late JuiceLogger savedLogger;
  late Level savedLevel;
  setUp(() {
    savedLogger = JuiceLoggerConfig.logger;
    savedLevel = JuiceLoggerConfig.minLevel;
    JuiceLoggerConfig.minLevel = Level.all;
  });
  tearDown(() {
    JuiceLoggerConfig.configureLogger(savedLogger);
    JuiceLoggerConfig.minLevel = savedLevel;
  });

  group('an emission carries the id of the run that made it', () {
    test('waiting and update: the id on the run\'s own span', () async {
      final log = CaptureLogger();
      final b = _B(logger: log);
      await b.send(_Work('a', Future<void>.value()));
      final id = _spanIds(log, '_Work').single;
      final emissions =
          log.typed('state_emission').where((e) => e['event'] == '_Work');
      expect(emissions.map((e) => e['status']), ['waiting', 'update']);
      expect(emissions.map((e) => e['executionId']), [id, id]);
      expect(log.typed('use_case_completed').single['executionId'], id);
      await b.close();
    });

    test('failure and cancel emissions carry it too', () async {
      final log = CaptureLogger();
      final b = _B(logger: log);
      await b.send(_FailNow());
      await b.send(_CancelNow());
      final failId = _spanIds(log, '_FailNow').single;
      final cancelId = _spanIds(log, '_CancelNow').single;
      expect(failId, isNot(cancelId));
      final byStatus = {
        for (final e in log.typed('state_emission')) e['status']: e,
      };
      expect(byStatus['failure']!['executionId'], failId);
      expect(byStatus['cancel']!['executionId'], cancelId);
      await b.close();
    });

    test(
        'two overlapping events of ONE type: each emission pairs with its '
        'own run, not with the type', () async {
      final log = CaptureLogger();
      final b = _B(logger: log);
      final gateA = Completer<void>();
      final gateB = Completer<void>();
      final a = b.send(_Work('a', gateA.future));
      final second = b.send(_Work('b', gateB.future));
      // Finish them in the opposite order they started.
      gateB.complete();
      await second;
      gateA.complete();
      await a;

      final ids = _spanIds(log, '_Work');
      expect(ids, hasLength(2));
      expect(ids[0], isNot(ids[1]));
      final updates = log
          .typed('state_emission')
          .where((e) => e['status'] == 'update')
          .toList();
      // 'b' landed first, and it names the SECOND run; 'a' the first.
      expect((updates[0]['state'] as _S).tag, 'b');
      expect(updates[0]['executionId'], ids[1]);
      expect((updates[1]['state'] as _S).tag, 'a');
      expect(updates[1]['executionId'], ids[0]);
      await b.close();
    });

    test('a skipped duplicate emission carries it', () async {
      final log = CaptureLogger();
      final b = _B(logger: log);
      await b.send(_Same());
      final skipped = log.typed('state_emission_skipped').single;
      expect(skipped['executionId'], _spanIds(log, '_Same').single);
      expect(log.typed('state_emission'), isEmpty);
      await b.close();
    });

    test(
        'an emission the restartable fence drops carries the SUPERSEDED '
        'run\'s id', () async {
      final log = CaptureLogger();
      final b = _B(logger: log);
      final gate = Completer<void>();
      final old = b.send(_Search(gate.future));
      b.send(_Search(Completer<void>().future)); // supersedes; never ends
      gate.complete();
      await old;
      final ids = _spanIds(log, '_Search');
      expect(ids, hasLength(2));
      final dropped = log.typed('state_emission_superseded').single;
      expect(dropped['executionId'], ids[0]);
      expect(dropped['status'], 'update');
      await b.close();
    });

    test(
        'a restartable run that is NOT superseded: every status kind it '
        'emits carries its id (the fenced context forwards it)', () async {
      final log = CaptureLogger();
      final b = _B(logger: log);
      await b.send(_AllKinds());
      final id = _spanIds(log, '_AllKinds').single;
      final emissions = log.typed('state_emission').toList();
      expect(emissions.map((e) => e['status']),
          ['waiting', 'failure', 'cancel', 'update']);
      expect(emissions.map((e) => e['executionId']), [id, id, id, id]);
      expect(log.typed('state_emission_skipped').single['executionId'], id);
      await b.close();
    });

    test(
        'a status emitted after close carries it; a re-emitted event\'s '
        'after-close entry carries none', () async {
      final log = CaptureLogger();
      final b = _B(logger: log);
      final gate = Completer<void>();
      final run = b.send(_Late(gate.future));
      await b.close();
      gate.complete();
      await run;
      final id = _spanIds(log, '_Late').single;
      final late = log.typed('emission_after_close').toList();
      expect(late.map((e) => e['status']), ['update', 'event']);
      expect(late[0]['executionId'], id);
      expect(late[1].containsKey('executionId'), isFalse,
          reason: 'emitEvent shares one closure across every run');
    });

    test('an inline use case\'s emission carries it', () async {
      final log = CaptureLogger();
      final b = _B(logger: log);
      await b.send(_Inline());
      expect(log.typed('state_emission').single['executionId'],
          _spanIds(log, '_Inline').single);
      await b.close();
    });

    test('an emission no run made carries none (seedState)', () async {
      final log = CaptureLogger();
      final b = _B(logger: log);
      b.seedState(const _S('seeded'));
      final seeded = log.typed('state_emission').single;
      expect(seeded.containsKey('executionId'), isFalse);
      await b.close();
    });

    test(
        'below the telemetry floor a failure emission is still recorded, '
        'with its id', () async {
      final log = CaptureLogger();
      JuiceLoggerConfig.minLevel = Level.warning;
      final b = _B(logger: log);
      await b.send(_FailNow());
      expect(log.typed('use_case_execution'), isEmpty,
          reason: 'the span itself is chatter');
      final failure = log.typed('state_emission').single;
      expect(failure['status'], 'failure');
      expect(failure['executionId'], isA<int>());
      await b.close();
    });
  });

  group('a dropped event is recorded', () {
    test(
        'droppable: the second event while the first runs is `event_dropped`, '
        'named, with the reason', () async {
      final log = CaptureLogger();
      final b = _B(logger: log);
      final gate = Completer<void>();
      final first = b.send(_Load(gate.future));
      await b.send(_Load(Future<void>.value())); // dropped: returns at once
      final dropped = log.typed('event_dropped').single;
      expect(dropped['event'], '_Load');
      expect(dropped['reason'], 'droppable: an earlier _Load is still running');
      expect(dropped['level'], Level.info);
      expect(dropped['message'], 'Event dropped');
      expect(_spanIds(log, '_Load'), hasLength(1),
          reason: 'no use case ran for the dropped event');

      gate.complete();
      await first;
      // The first is done: the next one runs, and nothing more is dropped.
      await b.send(_Load(Future<void>.value()));
      expect(log.typed('event_dropped'), hasLength(1));
      expect(_spanIds(log, '_Load'), hasLength(2));
      await b.close();
    });

    test('every drop is recorded, one entry each', () async {
      final log = CaptureLogger();
      final b = _B(logger: log);
      final gate = Completer<void>();
      final first = b.send(_Load(gate.future));
      b.send(_Load(Future<void>.value()));
      b.send(_Load(Future<void>.value()));
      b.send(_Load(Future<void>.value()));
      expect(log.typed('event_dropped'), hasLength(3));
      gate.complete();
      await first;
      await b.close();
    });

    test(
        'below the floor the entry is not built, and the drop itself is '
        'unchanged (sendAndWait still fails loud)', () async {
      final log = CaptureLogger();
      JuiceLoggerConfig.minLevel = Level.warning;
      final b = _B(logger: log);
      final gate = Completer<void>();
      final first = b.send(_Load(gate.future));
      await expectLater(
          b.sendAndWait(_Load(Future<void>.value())),
          throwsA(isA<StateError>()
              .having((e) => e.message, 'message', contains('dropped'))));
      expect(log.typed('event_dropped'), isEmpty);
      gate.complete();
      await first;
      await b.close();
    });

    test('the other modes drop nothing: no entry', () async {
      final log = CaptureLogger();
      final b = _B(logger: log);
      final seqGate = Completer<void>();
      final seq1 = b.send(_Seq(seqGate.future));
      final seq2 = b.send(_Seq(Future<void>.value())); // queued
      final workGate = Completer<void>();
      final work1 = b.send(_Work('a', workGate.future));
      final work2 = b.send(_Work('b', Future<void>.value())); // overlaps
      final old = b.send(_Search(Future<void>.value()));
      final fresh = b.send(_Search(Future<void>.value())); // supersedes
      seqGate.complete();
      workGate.complete();
      await Future.wait([seq1, seq2, work1, work2, old, fresh]);
      expect(log.typed('event_dropped'), isEmpty);
      await b.close();
    });
  });
}
