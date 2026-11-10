import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';
import 'package:juice/src/bloc/src/core/activity_probe.dart';
import '../support/capture_logger.dart';

/// `sendAfter` and `cancelSend`: the bloc owns the timer. A later call with
/// the same key replaces the pending one (that replace is a debounce); a
/// replace or a cancel is recorded as a dropped event; a close discards
/// what is pending and says so; nothing is ever sent synchronously, or
/// after the bloc started closing.

class _S extends BlocState {
  const _S({this.n = 0, this.text = '', this.runs = 0});
  final int n;
  final String text;
  final int runs;
}

class _Set extends EventBase {
  _Set(this.n);
  final int n;
}

class _Search extends EventBase {
  _Search(this.text);
  final String text;
}

/// Re-arms itself with the same key until it has run three times.
class _Poll extends EventBase {}

/// Handled once, it sends ITSELF again after a zero delay.
class _Again extends EventBase {
  var sentAgain = false;
}

class _SetUC extends BlocUseCase<_Bloc, _Set> {
  @override
  Future<void> execute(_Set e) async =>
      emitUpdate(newState: _S(n: e.n, runs: bloc.state.runs + 1));
}

class _SearchUC extends BlocUseCase<_Bloc, _Search> {
  @override
  Future<void> execute(_Search e) async =>
      emitUpdate(newState: _S(text: e.text, runs: bloc.state.runs + 1));
}

class _PollUC extends BlocUseCase<_Bloc, _Poll> {
  @override
  Future<void> execute(_Poll e) async {
    final runs = bloc.state.runs + 1;
    emitUpdate(newState: _S(runs: runs));
    if (runs < 3) {
      bloc.sendAfter(_Poll(), const Duration(milliseconds: 5), key: 'poll');
    }
  }
}

class _AgainUC extends BlocUseCase<_Bloc, _Again> {
  @override
  Future<void> execute(_Again e) async {
    emitUpdate(newState: _S(runs: bloc.state.runs + 1));
    if (!e.sentAgain) {
      e.sentAgain = true;
      bloc.sendAfter(e, Duration.zero);
    }
  }
}

class _Bloc extends JuiceBloc<_S> {
  _Bloc(this.log)
      : super(
          const _S(),
          [
            () => UseCaseBuilder(
                typeOfEvent: _Set,
                useCaseGenerator: () => _SetUC(),
                concurrency: EventConcurrency.concurrent),
            () => UseCaseBuilder(
                typeOfEvent: _Search,
                useCaseGenerator: () => _SearchUC(),
                concurrency: EventConcurrency.concurrent),
            () => UseCaseBuilder(
                typeOfEvent: _Poll,
                useCaseGenerator: () => _PollUC(),
                concurrency: EventConcurrency.concurrent),
            () => UseCaseBuilder(
                typeOfEvent: _Again,
                useCaseGenerator: () => _AgainUC(),
                concurrency: EventConcurrency.concurrent),
          ],
          const [],
          log,
        );

  final CaptureLogger log;
}

class _Src extends _Bloc {
  _Src(super.log);
}

class _Probe implements JuiceActivityProbe {
  final log = <String>[];

  @override
  void began(JuiceWork work) => log.add('began $work');

  @override
  void ended(JuiceWork work) => log.add('ended $work');
}

const _wait = Duration(seconds: 2);
const _soon = Duration(milliseconds: 20);
const _later = Duration(milliseconds: 80);

Future<void> _sleep(Duration d) => Future<void>.delayed(d);

void main() {
  late CaptureLogger log;
  late _Bloc bloc;
  late List<_S> states;

  setUp(() {
    log = CaptureLogger();
    bloc = _Bloc(log);
    states = [];
    addTearDown(bloc.tapEmissions((status) => states.add(status.state)));
    addTearDown(bloc.close);
  });

  Iterable<Map<String, dynamic>> dropped() => log.typed('event_dropped');
  Iterable<Map<String, dynamic>> ignored() =>
      log.where('bloc_lifecycle', 'event_ignored');

  group('sending', () {
    test('the event is sent once the delay has elapsed, and not before',
        () async {
      final pending = bloc.sendAfter(_Set(1), _later);
      expect(pending.isPending, isTrue);
      expect(pending.key, isNull);

      await _sleep(const Duration(milliseconds: 10));
      expect(bloc.state.n, 0);
      expect(pending.isPending, isTrue);

      await bloc.waitFor((s) => s.n == 1, timeout: _wait);
      expect(pending.isPending, isFalse);
      expect(dropped(), isEmpty);
    });

    test('a zero delay sends on the next timer turn, never synchronously',
        () async {
      final pending = bloc.sendAfter(_Set(1), Duration.zero);
      expect(bloc.state.n, 0);
      expect(pending.isPending, isTrue);

      await Future<void>.microtask(() {});
      expect(bloc.state.n, 0, reason: 'not on a microtask either');

      await pump();
      expect(bloc.state.n, 1);
      expect(pending.isPending, isFalse);
    });

    test('a negative delay throws, and nothing is pending', () async {
      expect(
        () => bloc.sendAfter(_Set(1), const Duration(milliseconds: -1)),
        throwsA(isA<ArgumentError>()
            .having((e) => e.name, 'name', 'delay')
            .having((e) => e.message, 'message',
                'sendAfter: a delay cannot be negative')),
      );
      await _sleep(_soon);
      expect(bloc.state.n, 0);
      expect(log.entries, isEmpty);
    });

    test('anonymous sends and different keys are independent', () async {
      bloc.sendAfter(_Set(1), _soon);
      bloc.sendAfter(_Set(2), _soon);
      bloc.sendAfter(_Set(3), _soon, key: 'a');
      bloc.sendAfter(_Set(4), _soon, key: 'b');

      await bloc.waitFor((s) => s.runs == 4, timeout: _wait);
      expect(states.map((s) => s.n), unorderedEquals([1, 2, 3, 4]));
      expect(dropped(), isEmpty);
    });
  });

  group('replacing', () {
    test(
        'the same key replaces the pending send: the earlier event is never '
        'sent, and the replace is recorded as a dropped event', () async {
      final first = bloc.sendAfter(_Set(1), _soon, key: 'k');
      final second = bloc.sendAfter(_Search('two'), _soon, key: 'k');
      expect(first.isPending, isFalse);
      expect(second.isPending, isTrue);
      expect(second.key, 'k');

      await bloc.waitFor((s) => s.text == 'two', timeout: _wait);
      await _sleep(_soon);

      expect(states, hasLength(1), reason: '_Set(1) was never sent');
      expect(dropped().single, {
        'message': 'Event dropped',
        'level': Level.info,
        'type': 'event_dropped',
        'bloc': '_Bloc',
        'event': '_Set',
        'key': 'k',
        'reason': 'sendAfter: replaced by a later _Search',
      });
    });

    test('a debounce: five keystrokes, one search, with the last text',
        () async {
      for (final text in ['j', 'ju', 'jui', 'juic', 'juice']) {
        bloc.sendAfter(_Search(text), const Duration(milliseconds: 40),
            key: 'search');
        await _sleep(const Duration(milliseconds: 4));
      }

      await bloc.waitFor((s) => s.text == 'juice', timeout: _wait);
      await _sleep(const Duration(milliseconds: 60));

      expect(states.map((s) => s.text), ['juice']);
      expect(dropped(), hasLength(4));
    });

    test('once a keyed send has fired, its key is free: nothing is replaced',
        () async {
      bloc.sendAfter(_Set(1), Duration.zero, key: 'k');
      await pump();
      expect(bloc.state.n, 1);

      bloc.sendAfter(_Set(2), Duration.zero, key: 'k');
      await pump();
      expect(bloc.state.n, 2);
      expect(dropped(), isEmpty);
    });

    test(
        'a use case that re-arms its own key: the send that just fired is '
        'not recorded as replaced', () async {
      bloc.sendAfter(_Poll(), Duration.zero, key: 'poll');

      await bloc.waitFor((s) => s.runs == 3, timeout: _wait);
      await _sleep(_soon);

      expect(bloc.state.runs, 3);
      expect(dropped(), isEmpty);
    });
  });

  group('cancelling', () {
    test('cancelSend by key: the event is not sent, and it is recorded',
        () async {
      final pending = bloc.sendAfter(_Set(1), _soon, key: 'k');
      bloc.cancelSend('k');
      expect(pending.isPending, isFalse);

      await _sleep(const Duration(milliseconds: 50));
      expect(bloc.state.n, 0);
      expect(dropped().single, {
        'message': 'Event dropped',
        'level': Level.info,
        'type': 'event_dropped',
        'bloc': '_Bloc',
        'event': '_Set',
        'key': 'k',
        'reason': 'sendAfter: cancelled',
      });
    });

    test('cancelSend with a key nothing is pending for does nothing', () async {
      bloc.cancelSend('nothing');
      bloc.sendAfter(_Set(1), Duration.zero, key: 'k');
      await pump();
      bloc.cancelSend('k'); // already sent
      expect(bloc.state.n, 1);
      expect(log.typed('event_dropped'), isEmpty);
    });

    test('the handle cancels an anonymous send; a second cancel does nothing',
        () async {
      final pending = bloc.sendAfter(_Set(1), _soon);
      final other = bloc.sendAfter(_Set(2), _soon);
      pending.cancel();
      pending.cancel();
      expect(pending.isPending, isFalse);

      await bloc.waitFor((s) => s.n == 2, timeout: _wait);
      await _sleep(_soon);
      expect(states.map((s) => s.n), [2]);
      expect(other.isPending, isFalse);
      expect(dropped().single['reason'], 'sendAfter: cancelled');
      expect(dropped().single.containsKey('key'), isFalse);
    });

    test('cancelling after the event was sent does nothing', () async {
      final pending = bloc.sendAfter(_Set(1), Duration.zero);
      await pump();
      pending.cancel();
      expect(bloc.state.n, 1);
      expect(dropped(), isEmpty);
    });

    test('cancelling a replaced send does not cancel its replacement',
        () async {
      final first = bloc.sendAfter(_Set(1), _soon, key: 'k');
      bloc.sendAfter(_Set(2), _soon, key: 'k');
      first.cancel();

      await bloc.waitFor((s) => s.n == 2, timeout: _wait);
      expect(dropped(), hasLength(1), reason: 'the replace, and only it');
    });
  });

  group('closing', () {
    test(
        'a close discards every pending send — none is sent early — and '
        'each is recorded as an ignored event', () async {
      final keyed = bloc.sendAfter(_Set(1), _soon, key: 'k');
      final anonymous = bloc.sendAfter(_Search('x'), _soon);

      final closing = bloc.close();
      // At once, before the close's first await.
      expect(keyed.isPending, isFalse);
      expect(anonymous.isPending, isFalse);
      await closing;
      await _sleep(const Duration(milliseconds: 50));

      expect(states, isEmpty);
      expect(ignored().toList(), [
        {
          'message': 'Event ignored',
          'level': Level.warning,
          'type': 'bloc_lifecycle',
          'action': 'event_ignored',
          'bloc': '_Bloc',
          'event': '_Set',
          'key': 'k',
          'reason': 'sendAfter: discarded, the bloc closed',
        },
        {
          'message': 'Event ignored',
          'level': Level.warning,
          'type': 'bloc_lifecycle',
          'action': 'event_ignored',
          'bloc': '_Bloc',
          'event': '_Search',
          'reason': 'sendAfter: discarded, the bloc closed',
        },
      ]);
      expect(dropped(), isEmpty);
    });

    test(
        'sendAfter on a closed bloc is refused with a record and returns a '
        'handle that was never pending', () async {
      await bloc.close();
      log.entries.clear();

      final refused = bloc.sendAfter(_Set(1), Duration.zero, key: 'k');
      expect(refused.isPending, isFalse);
      expect(refused.key, 'k');
      refused.cancel(); // nothing to cancel, nothing thrown
      bloc.cancelSend('k');
      await pump();

      expect(log.entries.single, {
        'message': 'Event ignored',
        'level': Level.warning,
        'type': 'bloc_lifecycle',
        'action': 'event_ignored',
        'bloc': '_Bloc',
        'event': '_Set',
        'key': 'k',
        'reason': 'sendAfter: bloc is closed',
      });
    });

    test('a close with nothing pending records no ignored event', () async {
      bloc.sendAfter(_Set(1), Duration.zero);
      await pump();
      await bloc.close();
      expect(ignored(), isEmpty);
    });
  });

  group('chains', () {
    test(
        'a delay starts a chain of its own: an event a reaction sent, sent '
        'again after a delay, carries no cause and no hop depth', () async {
      final src = _Src(CaptureLogger());
      addTearDown(src.close);
      final event = _Again();
      bloc.react(Reaction<_Src, _S>.changes((s) => s.n,
          source: src, send: (_) => event, atAttach: AtAttach.skip));

      await src.send(_Set(1));
      await bloc.waitFor((s) => s.runs == 2, timeout: _wait);

      final starts = log
          .typed('use_case_execution')
          .where((e) => e['event'] == '_Again')
          .toList();
      expect(starts, hasLength(2));
      expect(starts[0]['hopDepth'], 1);
      expect(starts[0].containsKey('causeExecutionId'), isTrue);
      expect(starts[1].containsKey('hopDepth'), isFalse);
      expect(starts[1].containsKey('causeExecutionId'), isFalse);
    });
  });

  group('what a test flow is told', () {
    late _Probe probe;

    setUp(() {
      probe = _Probe();
      JuiceActivityProbe.current = probe;
    });

    tearDown(() => JuiceActivityProbe.current = null);

    const delayed = 'delayed send _Set to _Bloc (after 0:00:00.000000)';

    test('delayed work describes itself', () {
      expect(
          JuiceWork.delayed('CartBloc', 'Save', const Duration(seconds: 2))
              .toString(),
          'delayed send Save to CartBloc (after 0:00:02.000000)');
    });

    test(
        'a delayed send is work from the call until its event is sent — the '
        'send begins before the delayed work ends', () async {
      bloc.sendAfter(_Set(1), Duration.zero);
      expect(probe.log, ['began $delayed']);

      await pump();
      expect(probe.log, [
        'began $delayed',
        'began send _Set to _Bloc',
        'ended $delayed',
        'ended send _Set to _Bloc',
      ]);
    });

    test('cancelled, replaced or discarded: the delayed work ends', () async {
      bloc.sendAfter(_Set(1), _later).cancel();
      bloc.sendAfter(_Set(2), _later, key: 'k');
      bloc.sendAfter(_Set(3), _later, key: 'k');
      expect(probe.log.where((l) => l.startsWith('began')), hasLength(3));
      expect(probe.log.where((l) => l.startsWith('ended')), hasLength(2));

      await bloc.close();
      expect(probe.log.where((l) => l.startsWith('ended')), hasLength(3));
      expect(
          probe.log.where((l) =>
              l.contains('send _Set to _Bloc') && !l.contains('delayed')),
          isEmpty);
    });

    test('a refused sendAfter is not work', () async {
      await bloc.close();
      bloc.sendAfter(_Set(1), Duration.zero);
      expect(probe.log, isEmpty);
    });
  });
}
