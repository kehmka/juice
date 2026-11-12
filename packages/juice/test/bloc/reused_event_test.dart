import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';
import '../support/capture_logger.dart';

/// Per-event state the framework keeps OFF the event (in Expandos keyed on
/// the instance) belongs to ONE send, not to the instance: an application
/// that keeps an event in a field and sends it again, or a reaction that
/// sends one cached instance each time, must not be answered or charged
/// for an earlier send of it. And a close hook another bloc owns must not
/// be able to abort this bloc's close.
///
/// Found by the 2026-11-11 review of the 2.1 branch, each reproduced before
/// it was fixed.

class _S extends BlocState {
  const _S(this.n);
  final int n;
  @override
  String toString() => '_S($n)';
}

// ---------- singleflight ----------
Completer<void> _gate = Completer<void>();

class _Pull extends EventBase {}

class _PullUseCase extends BlocUseCase<_Flights, _Pull> {
  @override
  Future<void> execute(_Pull event) async {
    await _gate.future;
    emitUpdate(newState: _S(bloc.state.n + 1));
  }
}

class _Flights extends JuiceBloc<_S> {
  _Flights(JuiceLogger log)
      : super(
          const _S(0),
          [
            () => UseCaseBuilder.typed(() => _PullUseCase(),
                concurrency: EventConcurrency.singleflight),
          ],
          const [],
          log,
        );
}

// ---------- reactions ----------
class _Inc extends EventBase {}

class _IncUseCase extends BlocUseCase<_Counter, _Inc> {
  @override
  Future<void> execute(_Inc event) async =>
      emitUpdate(newState: _S(bloc.state.n + 1));
}

class _Counter extends JuiceBloc<_S> {
  _Counter(JuiceLogger log)
      : super(
          const _S(0),
          [
            () => UseCaseBuilder.typed(() => _IncUseCase(),
                concurrency: EventConcurrency.sequential),
          ],
          const [],
          log,
        );
}

class _Note extends EventBase {}

class _NoteUseCase extends BlocUseCase<_Notes, _Note> {
  @override
  Future<void> execute(_Note event) async =>
      emitUpdate(newState: _S(bloc.state.n + 1));
}

class _Notes extends JuiceBloc<_S> {
  _Notes(JuiceLogger log)
      : super(
          const _S(0),
          [
            () => UseCaseBuilder.typed(() => _NoteUseCase(),
                concurrency: EventConcurrency.sequential),
          ],
          const [],
          log,
        );
}

/// A destination's logger that throws when told its reaction ended.
class _ThrowingLogger extends CaptureLogger {
  @override
  void record(JuiceTelemetry e) {
    super.record(e);
    if (e.kind == JuiceTelemetryKind.reactionEnded) {
      throw StateError('the logger broke');
    }
  }
}

void main() {
  group('singleflight', () {
    test(
        'an instance that once JOINED a flight, sent again later, leads its '
        'own flight and is answered by its own run', () async {
      final bloc = _Flights(CaptureLogger());
      addTearDown(bloc.close);

      final reused = _Pull();
      _gate = Completer<void>();
      final leader = bloc.send(_Pull());
      final joiner = bloc.send(reused); // joins the first flight
      _gate.complete();
      await Future.wait([leader, joiner]);
      expect(bloc.state.n, 1);

      _gate = Completer<void>();
      final waiting =
          bloc.sendAndWait(reused, timeout: const Duration(seconds: 2));
      var answeredEarly = false;
      unawaited(waiting.then((_) => answeredEarly = !_gate.isCompleted));
      await pump();
      expect(answeredEarly, isFalse,
          reason: 'answered before its own run emitted anything — by the '
              'flight it joined last time');
      _gate.complete();
      final status = await waiting;

      expect(identical(status.event, reused), isTrue);
      expect(status.state.n, 2);
    });

    test(
        'an instance that LED a flight, sent again later, is answered by its '
        'new run', () async {
      final bloc = _Flights(CaptureLogger());
      addTearDown(bloc.close);

      final reused = _Pull();
      _gate = Completer<void>()..complete();
      await bloc.sendAndWait(reused);
      _gate = Completer<void>();
      final waiting =
          bloc.sendAndWait(reused, timeout: const Duration(seconds: 2));
      await pump();
      _gate.complete();

      expect((await waiting).state.n, 2);
    });
  });

  group('a reaction\'s cause', () {
    test(
        'a cached instance a reaction chain sent, sent later by the app '
        'itself, starts at depth zero', () async {
      final log = CaptureLogger();
      final counter = _Counter(log);
      final notes = _Notes(log);
      addTearDown(counter.close);
      addTearDown(notes.close);
      final shared = _Inc();
      // A self-chain of eight hops that ends at n == 9, sending the SAME
      // instance each hop.
      counter.react(Reaction<_Counter, _S>.edge((o, s) => s.n != o.n && s.n < 9,
          source: counter, send: (_) => shared));
      // Another bloc reacts once the counter reaches ten.
      notes.react(Reaction<_Counter, _S>.edge((o, s) => s.n == 10,
          source: counter, send: (_) => _Note()));

      await counter.send(_Inc());
      await pump(20);
      expect(counter.state.n, 9);
      expect(log.where('reaction', 'refused'), isEmpty);

      await counter.send(shared);
      await pump(5);

      expect(counter.state.n, 10);
      expect(log.where('reaction', 'refused'), isEmpty,
          reason: 'a send the app made was charged the old chain\'s depth');
      expect(notes.state.n, 1);
    });

    test('a ring that sends one cached instance each hop is still refused',
        () async {
      final log = CaptureLogger();
      final counter = _Counter(log);
      addTearDown(counter.close);
      final shared = _Inc();
      counter.react(Reaction<_Counter, _S>.edge((o, s) => s.n != o.n,
          source: counter, send: (_) => shared));

      await counter.send(_Inc());
      await pump(40);

      expect(log.where('reaction', 'refused'), hasLength(1),
          reason: 'releasing the cause at the end of a run must not reset '
              'a chain that is still going');
      expect(counter.state.n, Reaction.maxHops + 1);
    });
  });

  group('close', () {
    test(
        'a close hook that throws is recorded, and the close goes on: the '
        'bloc closes and the waits behind the hook are failed at once',
        () async {
      final sourceLog = CaptureLogger();
      final source = _Counter(sourceLog);
      final destination = _Notes(_ThrowingLogger());
      addTearDown(destination.close);
      destination.react(Reaction<_Counter, _S>.edge((o, s) => true,
          source: source, send: (_) => _Note()));
      // Registered AFTER the reaction: its hook runs after the one that
      // throws.
      Object? waitError;
      unawaited(source
          .waitFor((s) => s.n == 99, timeout: const Duration(seconds: 3))
          .then<void>((_) {}, onError: (Object e) => waitError = e));

      await source.close();
      await pump();

      expect(source.isClosed, isTrue);
      expect(waitError, isA<StateError>(),
          reason: 'the pending waitFor waited out its timeout');
      final failed = sourceLog.where('bloc_close_error').single;
      expect(failed['reason'], 'a close hook threw');
      expect(failed['error'], isA<StateError>());
    });
  });
}
