import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';
import 'package:juice/testing.dart';
import '../support/capture_logger.dart';

/// `EventConcurrency.singleflight`: an event arriving while one of its type
/// (and join key) is running JOINS that run. It does not run and it is not
/// dropped: its `send` completes with the running one's, `sendAndWait`
/// answers with the running one's status, `sendForResult` returns the
/// running one's value or throws its error.

class _S extends BlocState {
  const _S({this.runs = 0, this.note = ''});
  final int runs;
  final String note;
  @override
  String toString() => '_S($runs, $note)';
}

/// Waits for [gate], then succeeds with the number of runs so far.
class _Refresh extends ResultEvent<int> {
  _Refresh(this.gate);
  final Future<void> gate;
}

/// Waits for [gate], then fails.
class _Broken extends ResultEvent<int> {
  _Broken(this.gate);
  final Future<void> gate;
}

/// Emits its answer at once, emits again at [progress], and keeps working
/// until [gate].
class _EarlyAnswer extends ResultEvent<int> {
  _EarlyAnswer(this.gate, {Future<void>? progress})
      : progress = progress ?? Future<void>.value();
  final Future<void> gate;
  final Future<void> progress;
}

/// Joins by [permission]: one prompt per permission.
class _Ask extends ResultEvent<String> {
  _Ask(this.permission, this.gate);
  final String permission;
  final Future<void> gate;
}

/// Not a result event.
class _Plain extends EventBase {
  _Plain(this.gate);
  final Future<void> gate;
}

/// Emits a waiting status, then nothing else.
class _Silent extends EventBase {
  _Silent(this.gate);
  final Future<void> gate;
}

/// Sends another of itself from inside its own run, then finishes.
class _Nested extends EventBase {}

class _BadKey extends EventBase {}

class _RefreshUC extends BlocUseCase<_Bloc, _Refresh> {
  @override
  Future<void> execute(_Refresh e) async {
    await e.gate;
    final runs = bloc.state.runs + 1;
    emitUpdate(newState: _S(runs: runs, note: 'refreshed'));
    e.succeed(runs);
  }
}

class _BrokenUC extends BlocUseCase<_Bloc, _Broken> {
  @override
  Future<void> execute(_Broken e) async {
    await e.gate;
    final error = StateError('refresh failed');
    emitFailure(
        newState: _S(runs: bloc.state.runs + 1, note: 'failed'), error: error);
  }
}

class _EarlyAnswerUC extends BlocUseCase<_Bloc, _EarlyAnswer> {
  @override
  Future<void> execute(_EarlyAnswer e) async {
    final runs = bloc.state.runs + 1;
    emitUpdate(newState: _S(runs: runs, note: 'answered early'));
    await e.progress;
    emitUpdate(newState: _S(runs: runs, note: 'still working'));
    await e.gate;
    e.succeed(runs * 100);
  }
}

class _AskUC extends BlocUseCase<_Bloc, _Ask> {
  @override
  Future<void> execute(_Ask e) async {
    await e.gate;
    emitUpdate(newState: _S(runs: bloc.state.runs + 1, note: e.permission));
    e.succeed('${e.permission}: granted');
  }
}

class _PlainUC extends BlocUseCase<_Bloc, _Plain> {
  @override
  Future<void> execute(_Plain e) async {
    await e.gate;
    emitUpdate(newState: _S(runs: bloc.state.runs + 1, note: 'plain'));
  }
}

class _SilentUC extends BlocUseCase<_Bloc, _Silent> {
  @override
  Future<void> execute(_Silent e) async {
    emitWaiting();
    await e.gate;
  }
}

class _NestedUC extends BlocUseCase<_Bloc, _Nested> {
  @override
  Future<void> execute(_Nested e) async {
    // Synchronously, before this run's first await.
    bloc.send(_Nested());
    emitUpdate(newState: _S(runs: bloc.state.runs + 1, note: 'nested'));
  }
}

class _BadKeyUC extends BlocUseCase<_Bloc, _BadKey> {
  @override
  Future<void> execute(_BadKey e) async => emitUpdate();
}

class _Bloc extends JuiceBloc<_S> {
  _Bloc([JuiceLogger? logger])
      : super(
          const _S(),
          [
            () => UseCaseBuilder(
                typeOfEvent: _Refresh,
                useCaseGenerator: () => _RefreshUC(),
                concurrency: EventConcurrency.singleflight),
            () => UseCaseBuilder(
                typeOfEvent: _Broken,
                useCaseGenerator: () => _BrokenUC(),
                concurrency: EventConcurrency.singleflight),
            () => UseCaseBuilder(
                typeOfEvent: _EarlyAnswer,
                useCaseGenerator: () => _EarlyAnswerUC(),
                concurrency: EventConcurrency.singleflight),
            // Typed: the key reads the event without a cast.
            () => UseCaseBuilder.typed(() => _AskUC(),
                concurrency: EventConcurrency.singleflight,
                joinKey: (e) => e.permission),
            () => UseCaseBuilder(
                typeOfEvent: _Plain,
                useCaseGenerator: () => _PlainUC(),
                concurrency: EventConcurrency.singleflight),
            () => UseCaseBuilder(
                typeOfEvent: _Silent,
                useCaseGenerator: () => _SilentUC(),
                concurrency: EventConcurrency.singleflight),
            () => UseCaseBuilder(
                typeOfEvent: _Nested,
                useCaseGenerator: () => _NestedUC(),
                concurrency: EventConcurrency.singleflight),
            () => UseCaseBuilder(
                typeOfEvent: _BadKey,
                useCaseGenerator: () => _BadKeyUC(),
                concurrency: EventConcurrency.singleflight,
                joinKey: (e) => throw StateError('the key broke')),
          ],
          const [],
          logger,
        );
}

const _wait = Duration(seconds: 2);

void main() {
  late CaptureLogger log;
  late _Bloc bloc;

  setUp(() {
    log = CaptureLogger();
    bloc = _Bloc(log);
    addTearDown(bloc.close);
  });

  Iterable<Map<String, dynamic>> joined() => log.typed('event_joined');

  group('joining', () {
    test(
        'a second event does not run and is not dropped: its send completes '
        "with the first's", () async {
      final gate = Completer<void>();
      var firstDone = false;
      var secondDone = false;

      final first = bloc.send(_Plain(gate.future))
        ..then((_) => firstDone = true);
      final second = bloc.send(_Plain(gate.future))
        ..then((_) => secondDone = true);
      await pump();
      expect(firstDone, isFalse);
      expect(secondDone, isFalse, reason: 'a dropped event returns at once');

      gate.complete();
      await Future.wait([first, second]);
      expect(bloc.state.runs, 1, reason: 'one flight');
      expect(log.typed('event_dropped'), isEmpty);
    });

    test("sendAndWait on a joined event answers with the running one's status",
        () async {
      final gate = Completer<void>();
      final leader = _Refresh(gate.future);

      final first = bloc.sendAndWait(leader, timeout: _wait);
      final second = bloc.sendAndWait(_Refresh(gate.future), timeout: _wait);
      gate.complete();
      final statuses = await Future.wait([first, second]);

      expect(identical(statuses[0], statuses[1]), isTrue);
      expect(statuses[1], isA<UpdatingStatus<_S>>());
      expect(identical(statuses[1].event, leader), isTrue,
          reason: 'the status is the one emitted for the event that ran');
      expect(bloc.state.runs, 1);
    });

    test("sendForResult: every caller gets the one flight's value", () async {
      final gate = Completer<void>();

      final callers = [
        for (var i = 0; i < 4; i++)
          bloc.sendForResult(_Refresh(gate.future), timeout: _wait),
      ];
      gate.complete();

      expect(await Future.wait(callers), [1, 1, 1, 1]);
      expect(bloc.state.runs, 1);
    });

    test("sendForResult: every caller gets the one flight's error", () async {
      final gate = Completer<void>();

      final callers = [
        for (var i = 0; i < 3; i++)
          bloc.sendForResult(_Broken(gate.future), timeout: _wait),
      ];
      final outcomes = [
        for (final caller in callers)
          expectLater(
              caller,
              throwsA(isA<StateError>()
                  .having((e) => e.message, 'message', 'refresh failed'))),
      ];
      gate.complete();
      await Future.wait(outcomes);

      expect(bloc.state.runs, 1);
    });

    test(
        'an event that joins AFTER the running one emitted its answer is '
        'answered with it at once, and still gets the value when it comes',
        () async {
      final gate = Completer<void>();
      final leader = _EarlyAnswer(gate.future);
      final first = bloc.sendForResult(leader, timeout: _wait);
      await pump();
      expect(bloc.state.note, 'still working');

      final late_ = _EarlyAnswer(gate.future);
      final status = await bloc.sendAndWait(late_, timeout: _wait);
      expect(status, isA<UpdatingStatus<_S>>());
      expect(identical(status.event, leader), isTrue);
      expect(late_.isCompleted, isFalse, reason: 'the run is still going');

      final third =
          bloc.sendForResult(_EarlyAnswer(gate.future), timeout: _wait);
      gate.complete();
      expect(await first, 100);
      expect(await late_.result, 100);
      expect(await third, 100);
      expect(bloc.state.runs, 1);
    });

    test(
        'the answer is the FIRST status the running event emitted, however '
        'many it has emitted since', () async {
      final gate = Completer<void>();
      final progress = Completer<void>();
      final leader = _EarlyAnswer(gate.future, progress: progress.future);
      final first = bloc.sendAndWait(leader, timeout: _wait);
      await pump();
      progress.complete();
      await pump();
      expect(bloc.state.note, 'still working');

      final status = await bloc.sendAndWait(
          _EarlyAnswer(gate.future, progress: progress.future),
          timeout: _wait);

      expect(status.state.note, 'answered early');
      expect(identical(status, await first), isTrue);
      gate.complete();
    });

    test(
        "an event that joined is failed with the running one's error even "
        'when nobody waits on it through the bloc', () async {
      final gate = Completer<void>();
      final leader = bloc.sendForResult(_Broken(gate.future), timeout: _wait);
      final joined = _Broken(gate.future);
      bloc.send(joined);
      final refreshFailed = throwsA(isA<StateError>()
          .having((e) => e.message, 'message', 'refresh failed'));
      final outcomes = [
        expectLater(leader, refreshFailed),
        expectLater(joined.result, refreshFailed),
      ];
      gate.complete();
      await Future.wait(outcomes);
    });

    test(
        'a waiting status is not the answer; a run that emits nothing else '
        'fails the wait of everyone who joined it', () async {
      final gate = Completer<void>();
      final first = bloc.sendAndWait(_Silent(gate.future), timeout: _wait);
      final second = bloc.sendAndWait(_Silent(gate.future), timeout: _wait);
      final outcomes = [
        for (final wait in [first, second])
          expectLater(
              wait,
              throwsA(isA<StateError>().having((e) => e.message, 'message',
                  contains('finished without a terminal status')))),
      ];
      gate.complete();
      await Future.wait(outcomes);
    });

    test('when the flight is over the next event runs: a new flight', () async {
      expect(await bloc.sendForResult(_Refresh(Future.value())), 1);
      expect(await bloc.sendForResult(_Refresh(Future.value())), 2);
      expect(joined(), isEmpty);
    });

    test(
        'an event of the same kind sent from inside the run joins it — it '
        'does not start a second run inside the first', () async {
      await bloc.send(_Nested());
      await pump();
      expect(bloc.state.runs, 1);
      expect(joined(), hasLength(1));
    });

    test('closing the bloc fails the wait of an event that joined', () async {
      final gate = Completer<void>();
      final first = bloc.sendAndWait(_Refresh(gate.future), timeout: _wait);
      final second = bloc.sendAndWait(_Refresh(gate.future), timeout: _wait);
      final outcomes = [
        for (final wait in [first, second])
          expectLater(
              wait,
              throwsA(isA<StateError>().having((e) => e.message, 'message',
                  contains('closed while sendAndWait(_Refresh) was pending')))),
      ];
      await bloc.close();
      await Future.wait(outcomes);
      gate.complete();
    });
  });

  group('the join key', () {
    test(
        'events join only when their keys are equal; different keys run '
        'side by side', () async {
      final camera = Completer<void>();
      final mic = Completer<void>();

      final cameraOne = bloc.sendForResult(_Ask('camera', camera.future));
      final cameraTwo = bloc.sendForResult(_Ask('camera', camera.future));
      final micOne = bloc.sendForResult(_Ask('mic', mic.future));

      mic.complete();
      expect(await micOne, 'mic: granted');
      expect(bloc.state.runs, 1, reason: 'mic ran beside the camera prompt');

      camera.complete();
      expect(await Future.wait([cameraOne, cameraTwo]),
          ['camera: granted', 'camera: granted']);
      expect(bloc.state.runs, 2, reason: 'one prompt per permission');
    });

    test(
        'a key only means something with singleflight: any other mode '
        'refuses it, from either constructor', () {
      final refused = throwsA(isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          'UseCaseBuilder for _Refresh: joinKey only means something with '
              'EventConcurrency.singleflight, and this builder is droppable'));
      expect(
          () => UseCaseBuilder(
              typeOfEvent: _Refresh,
              useCaseGenerator: () => _RefreshUC(),
              concurrency: EventConcurrency.droppable,
              joinKey: (e) => 1),
          refused);
      expect(
          () => UseCaseBuilder.typed(() => _RefreshUC(),
              concurrency: EventConcurrency.droppable, joinKey: (e) => 1),
          refused);
    });

    test(
        'a key function that throws fails the send — as a failed future, '
        'never into the sender — and nothing is left in flight', () async {
      final Future<void> sent;
      try {
        sent = bloc.send(_BadKey());
      } catch (_) {
        fail('send threw synchronously');
      }
      await expectLater(
          sent,
          throwsA(isA<StateError>()
              .having((e) => e.message, 'message', 'the key broke')));
      await expectLater(
          bloc.sendAndWait(_BadKey(), timeout: _wait),
          throwsA(isA<StateError>()
              .having((e) => e.message, 'message', 'the key broke')));
    });

    test('a join key that throws is RECORDED, not only a failed future',
        () async {
      // The usual send is not awaited: without the record the failure
      // would reach nothing but an uncaught-error handler.
      final sent = bloc.send(_BadKey());
      await expectLater(sent, throwsStateError);

      final recorded = log.where('join_key_error').toList();
      expect(recorded, hasLength(1));
      expect(recorded.single['event'], '_BadKey');
      expect(recorded.single['error'], isA<StateError>());
    });
  });

  group('telemetry', () {
    test('a join is recorded, with the key as text; the run itself is not',
        () async {
      final gate = Completer<void>();
      bloc.send(_Ask('camera', gate.future));
      bloc.send(_Ask('camera', gate.future));
      bloc.send(_Plain(gate.future));
      bloc.send(_Plain(gate.future));
      gate.complete();
      await pump(2);

      expect(joined().toList(), [
        {
          'message': 'Event joined',
          'level': Level.info,
          'type': 'event_joined',
          'bloc': '_Bloc',
          'event': '_Ask',
          'key': 'camera',
        },
        {
          'message': 'Event joined',
          'level': Level.info,
          'type': 'event_joined',
          'bloc': '_Bloc',
          'event': '_Plain',
        },
      ]);
    });
  });

  group('in a test flow', () {
    juiceFlowTest('joined sends are waited for like any other', (flow) async {
      final b = flow.add(_Bloc());
      final gate = Completer<void>();

      b.send(_Plain(gate.future));
      b.send(_Plain(gate.future));
      gate.complete();
      await flow.settle();

      flow.expect(b, hasLength(1));
    });
  });
}
