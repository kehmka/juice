import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';

/// `EventConcurrency.restartable` (2.0.0): a new same-type event supersedes
/// the in-flight run and starts at once. The superseded run is FENCED —
/// every emission and navigation it attempts is dropped and logged — its
/// stream bindings are cancelled, its CancellableEvent is cancelled, and
/// `sendAndWait` on it answers with a CancelingStatus. Side effects already
/// performed are not rolled back. Pinned here, every path.

class _S extends BlocState {
  const _S(this.log, {this.value = ''});
  final List<String> log;
  final String value;
}

/// A search: waits for [gate] (the test controls when the "request"
/// returns), then emits its query. Plain EventBase: cooperation is by
/// `isSuperseded`.
class _Search extends EventBase {
  _Search(this.query, this.gate);
  final String query;
  final Future<void> gate;
}

/// A cancellable long loop: supersede cancels the event itself.
class _Scrub extends CancellableEvent {
  _Scrub(this.steps, this.tick);
  final int steps;
  final Future<void> Function() tick;
  int stepsRun = 0;
}

/// A run that fails after it was superseded.
class _Fail extends EventBase {
  _Fail(this.gate);
  final Future<void> gate;
}

/// A run that binds a stream and stays in flight for the binding's life —
/// the shape that lets restartable supersede the binding (a run that has
/// already RETURNED is not in flight, so nothing supersedes it; its binding
/// belongs to the bloc until unbound or replaced by key).
class _Watch extends EventBase {
  _Watch(this.source);
  final Stream<int> source;
}

class _Got extends EventBase {
  _Got(this.v);
  final int v;
}

/// Sequential and droppable stay untouched by the fence machinery.
class _Seq extends EventBase {
  _Seq(this.gate);
  final Future<void> gate;
}

/// The superseded run tries EVERY emission kind after the fence closed.
class _Everything extends EventBase {
  _Everything(this.gate);
  final Future<void> gate;
}

class _SearchUC extends BlocUseCase<_B, _Search> {
  @override
  Future<void> execute(_Search e) async {
    emitWaiting(groupsToRebuild: {'g'});
    await e.gate;
    bloc.observedSuperseded[e.query] = isSuperseded;
    if (isSuperseded) return;
    emitUpdate(
        newState: _S([...bloc.state.log, 'result:${e.query}'], value: e.query),
        groupsToRebuild: {'g'});
  }
}

class _ScrubUC extends BlocUseCase<_B, _Scrub> {
  @override
  Future<void> execute(_Scrub e) async {
    for (var i = 0; i < e.steps; i++) {
      if (e.isCancelled) return;
      e.stepsRun++;
      await e.tick();
    }
    emitUpdate(
        newState: _S([...bloc.state.log, 'scrubbed']), groupsToRebuild: {'g'});
  }
}

class _FailUC extends BlocUseCase<_B, _Fail> {
  @override
  Future<void> execute(_Fail e) async {
    await e.gate;
    throw StateError('late failure');
  }
}

class _WatchUC extends BlocUseCase<_B, _Watch> {
  @override
  Future<void> execute(_Watch e) async {
    final binding = bloc.bindStream<int>(e.source, (v) => bloc.send(_Got(v)));
    await binding.done; // in flight until the stream ends or we are superseded
  }
}

class _GotUC extends BlocUseCase<_B, _Got> {
  @override
  Future<void> execute(_Got e) async => emitUpdate(
      newState: _S([...bloc.state.log, 'got:${e.v}']), groupsToRebuild: {'g'});
}

class _SeqUC extends BlocUseCase<_B, _Seq> {
  @override
  Future<void> execute(_Seq e) async {
    await e.gate;
    bloc.observedSuperseded['seq'] = isSuperseded;
    emitUpdate(
        newState: _S([...bloc.state.log, 'seq']), groupsToRebuild: {'g'});
  }
}

class _EverythingUC extends BlocUseCase<_B, _Everything> {
  @override
  Future<void> execute(_Everything e) async {
    await e.gate;
    // All of these must be dropped once superseded.
    emitUpdate(
        newState: _S([...bloc.state.log, 'update']),
        groupsToRebuild: {'g'},
        aviatorName: 'home');
    emitWaiting(newState: _S([...bloc.state.log, 'waiting']));
    emitFailure(
        newState: _S([...bloc.state.log, 'failure']), error: StateError('x'));
    emitCancel(newState: _S([...bloc.state.log, 'cancel']));
    emitEvent(event: _Got(99));
  }
}

class _B extends JuiceBloc<_S> {
  _B({JuiceLogger? logger})
      : super(
          const _S([]),
          [
            () => UseCaseBuilder.typed(() => _SearchUC(),
                concurrency: EventConcurrency.restartable),
            () => UseCaseBuilder.typed(() => _ScrubUC(),
                concurrency: EventConcurrency.restartable),
            () => UseCaseBuilder.typed(() => _FailUC(),
                concurrency: EventConcurrency.restartable),
            () => UseCaseBuilder.typed(() => _WatchUC(),
                concurrency: EventConcurrency.restartable),
            () => UseCaseBuilder.typed(() => _EverythingUC(),
                concurrency: EventConcurrency.restartable),
            () => UseCaseBuilder.typed(() => _GotUC(),
                concurrency: EventConcurrency.sequential),
            () => UseCaseBuilder.typed(() => _SeqUC(),
                concurrency: EventConcurrency.sequential),
          ],
          [
            () => Aviator(name: 'home', navigateWhere: (_) => _navigated++),
          ],
          logger,
          BlocErrorHandler(onError: (m, {error, stackTrace}) {}),
        );

  final observedSuperseded = <String, bool>{};
}

/// Navigations the test aviator saw (reset per test).
int _navigated = 0;

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
  Iterable<Map<String, dynamic>> typed(String type) =>
      entries.where((e) => e['type'] == type);
}

Future<void> pump([int n = 1]) async {
  for (var i = 0; i < n; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late JuiceLogger savedLogger;
  late Level savedLevel;
  setUp(() {
    savedLogger = JuiceLoggerConfig.logger;
    savedLevel = JuiceLoggerConfig.minLevel;
    JuiceLoggerConfig.minLevel = Level.all;
    _navigated = 0;
  });
  tearDown(() {
    JuiceLoggerConfig.configureLogger(savedLogger);
    JuiceLoggerConfig.minLevel = savedLevel;
  });

  group('supersede', () {
    test(
        'a new same-type event starts at once and the old run is fenced: '
        'only the latest result lands', () async {
      final b = _B(logger: _Log());
      final g1 = Completer<void>();
      final g2 = Completer<void>();
      final first = b.send(_Search('a', g1.future));
      final second = b.send(_Search('ab', g2.future));
      await pump();
      expect(b.observedSuperseded, isEmpty,
          reason: 'both runs are suspended at their gate — the second '
              'started without waiting for the first');
      g2.complete(); // the latest returns first
      await second;
      expect(b.state.value, 'ab');
      g1.complete(); // the stale one returns late
      await first;
      expect(b.observedSuperseded['a'], isTrue);
      expect(b.observedSuperseded['ab'], isFalse);
      expect(b.state.value, 'ab', reason: 'the stale result never landed');
      expect(b.state.log, ['result:ab']);
      await b.close();
    });

    test(
        'three rapid events: only the last run emits, in whichever order '
        'the requests return', () async {
      final b = _B(logger: _Log());
      final gates = [for (var i = 0; i < 3; i++) Completer<void>()];
      final sends = [
        for (var i = 0; i < 3; i++) b.send(_Search('q$i', gates[i].future))
      ];
      gates[2].complete();
      gates[0].complete();
      gates[1].complete();
      await Future.wait(sends);
      expect(b.state.log, ['result:q2']);
      expect(b.observedSuperseded, {'q0': true, 'q1': true, 'q2': false});
      await b.close();
    });

    test(
        'every emission kind and navigation attempted by a superseded run '
        'is dropped and logged with what was dropped', () async {
      final log = _Log();
      final b = _B(logger: log);
      final g1 = Completer<void>();
      final g2 = Completer<void>();
      final old = b.send(_Everything(g1.future));
      final fresh = b.send(_Everything(g2.future));
      g1.complete();
      await old;
      expect(b.state.log, isEmpty, reason: 'nothing from the old run');
      expect(_navigated, 0, reason: 'navigation fenced too');
      final dropped =
          log.typed('state_emission_superseded').map((e) => e['what']).toList();
      expect(
          dropped,
          containsAll(
              ['update', 'navigate', 'waiting', 'failure', 'cancel', 'event']));
      g2.complete();
      await fresh;
      expect(b.state.log, contains('update'), reason: 'the winner emits');
      expect(_navigated, 1);
      await b.close();
    });

    test(
        'a superseded CancellableEvent is cancelled, so a cooperative loop '
        'bails early', () async {
      final b = _B(logger: _Log());
      var ticks = 0;
      final tickGate = <Completer<void>>[];
      Future<void> tick() {
        ticks++;
        final c = Completer<void>();
        tickGate.add(c);
        return c.future;
      }

      final slow = _Scrub(10, tick);
      final slowRun = b.send(slow);
      await pump();
      expect(slow.stepsRun, 1);
      final fast = _Scrub(1, () async {});
      await b.send(fast);
      expect(slow.isCancelled, isTrue);
      expect(b.isSuperseded(slow), isTrue);
      expect(b.isSuperseded(fast), isFalse);
      tickGate.single.complete();
      await slowRun;
      expect(slow.stepsRun, 1, reason: 'bailed on the cancel check');
      expect(ticks, 1);
      expect(b.state.log, ['scrubbed'], reason: 'only the winner emitted');
      await b.close();
    });

    test(
        'a run that errors after being superseded still closes its span, '
        'flagged superseded', () async {
      final log = _Log();
      final b = _B(logger: log);
      final g1 = Completer<void>();
      final old = b.send(_Fail(g1.future));
      b.send(_Fail(Completer<void>().future)); // the winner never returns
      g1.complete();
      await old;
      final err = log.typed('use_case_error').firstWhere(
          (e) => e['event'] == '_Fail' && e.containsKey('executionId'));
      expect(err['superseded'], isTrue);
      await b.close();
    });

    test(
        'a completed superseded run flags its end entry; the winner does '
        'not', () async {
      final log = _Log();
      final b = _B(logger: log);
      final g1 = Completer<void>();
      final g2 = Completer<void>();
      final old = b.send(_Search('x', g1.future));
      final fresh = b.send(_Search('xy', g2.future));
      g1.complete();
      g2.complete();
      await Future.wait([old, fresh]);
      final ends = log.typed('use_case_completed').toList();
      expect(ends, hasLength(2));
      expect(ends.where((e) => e['superseded'] == true), hasLength(1));
      await b.close();
    });

    test('the supersede itself is logged', () async {
      final log = _Log();
      final b = _B(logger: log);
      b.send(_Search('a', Completer<void>().future));
      await b.send(_Search('b', Future.value()));
      final gates = <Completer<void>>[];
      final stuck = b.send(_Scrub(5, () {
        final c = Completer<void>();
        gates.add(c);
        return c.future;
      }));
      await pump();
      await b.send(_Scrub(1, () async {}));
      gates.single.complete(); // the stuck loop wakes, sees the cancel, returns
      await stuck;
      final entries = log.typed('use_case_superseded').toList();
      expect(entries.map((e) => e['event']), ['_Search', '_Scrub']);
      expect(entries.map((e) => e['cancellable']), [false, true]);
      await b.close();
    });

    test('supersede chatter is not built below the telemetry floor', () async {
      final log = _Log();
      JuiceLoggerConfig.configureLogger(log);
      JuiceLoggerConfig.minLevel = Level.warning;
      final b = _B(logger: log);
      final g1 = Completer<void>();
      final old = b.send(_Everything(g1.future));
      b.send(_Everything(Completer<void>().future));
      g1.complete();
      await old;
      expect(log.typed('use_case_superseded'), isEmpty);
      expect(log.typed('state_emission_superseded'), isEmpty);
      expect(b.state.log, isEmpty, reason: 'still fenced');
      await b.close();
    });
  });

  group('stream bindings', () {
    test(
        'bindings created by the superseded run are cancelled; the '
        'winner\'s survive', () async {
      final b = _B(logger: _Log());
      final c1 = StreamController<int>();
      final c2 = StreamController<int>();
      final first = b.send(_Watch(c1.stream));
      await pump();
      expect(b.activeBindingCount, 1);
      final second = b.send(_Watch(c2.stream));
      await pump();
      expect(b.activeBindingCount, 1, reason: 'the old binding is gone');
      await first.timeout(const Duration(seconds: 1),
          onTimeout: () => fail('the superseded run should have returned: '
              'its binding was cancelled, so binding.done completed'));
      c1.add(1);
      c2.add(2);
      await pump(3);
      expect(b.state.log, ['got:2']);
      await c1.close();
      await c2.close();
      await b.close();
      await second;
    });

    test(
        'a binding made outside any restartable run has no run and is '
        'untouched by a supersede', () async {
      final b = _B(logger: _Log());
      final c = StreamController<int>();
      final binding = b.bindStream<int>(c.stream, (_) {});
      expect(binding.run, isNull);
      b.send(_Search('a', Completer<void>().future));
      await b.send(_Search('b', Future.value()));
      expect(binding.isActive, isTrue);
      await c.close();
      await b.close();
    });
  });

  group('sendAndWait', () {
    test(
        'answers a superseded event with a CancelingStatus for THAT event, '
        'without putting it on the stream, and the winner normally', () async {
      final b = _B(logger: _Log());
      final emitted = <StreamStatus<_S>>[];
      final sub = b.stream.listen(emitted.add);
      final g1 = Completer<void>();
      final old = _Search('a', g1.future);
      final oldWait = b.sendAndWait(old);
      final winner = b.sendAndWait(_Search('ab', Future.value()));
      final oldStatus = await oldWait;
      expect(oldStatus, isA<CancelingStatus<_S>>());
      expect(identical(oldStatus.event, old), isTrue);
      final winStatus = await winner;
      expect(winStatus, isA<UpdatingStatus<_S>>());
      expect(winStatus.state.value, 'ab');
      await pump();
      expect(emitted.whereType<CancelingStatus<_S>>(), isEmpty,
          reason: 'the canceling answer was not emitted');
      g1.complete();
      await sub.cancel();
      await b.close();
    });

    test('a restartable event that is never superseded resolves normally',
        () async {
      final b = _B(logger: _Log());
      final status = await b.sendAndWait(_Search('solo', Future.value()));
      expect(status, isA<UpdatingStatus<_S>>());
      expect(status.state.value, 'solo');
      await b.close();
    });
  });

  group('other modes and lifecycle', () {
    test(
        'sequential is untouched: isSuperseded is false and every run '
        'emits', () async {
      final b = _B(logger: _Log());
      final g = Completer<void>();
      final first = b.send(_Seq(g.future));
      final second = b.send(_Seq(Future.value()));
      g.complete();
      await Future.wait([first, second]);
      expect(b.state.log, ['seq', 'seq']);
      expect(b.observedSuperseded['seq'], isFalse);
      expect(b.isSuperseded(_Seq(Future.value())), isFalse,
          reason: 'an event never dispatched restartable');
      await b.close();
    });

    test(
        'a restartable run in flight at close hits the close fence; a '
        'restartable event sent after close is ignored', () async {
      final log = _Log();
      final b = _B(logger: log);
      final g = Completer<void>();
      final inFlight = b.send(_Search('late', g.future));
      await b.close();
      g.complete();
      await inFlight;
      expect(b.state.log, isEmpty);
      await b.send(_Search('after', Future.value()));
      expect(
          log
              .typed('bloc_lifecycle')
              .any((e) => e['action'] == 'event_ignored'),
          isTrue);
    });
  });
}
