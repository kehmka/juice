import 'package:logger/web.dart' show Level;
import 'package:matcher/expect.dart' as m;
import 'package:meta/meta.dart';
import 'package:test_api/scaffolding.dart' as scaffolding;

import '../bloc/bloc.dart';
import '../bloc/src/core/activity_probe.dart';
import '../bloc/src/core/type_names.dart';
import 'juice_test.dart';

/// Declares a test of SEVERAL blocs and the reactions between them.
///
/// [juiceTest] builds one bloc. A flow holds as many as the test hands it,
/// knows when every bloc in the process is idle, and is exhaustive across
/// all of them: it fails on any emission the test did not assert.
///
/// ```dart
/// juiceFlowTest('a settings change reaches notes', (flow) async {
///   final settings = flow.register<SettingsBloc>(() => SettingsBloc());
///   final notes = flow.register<NotesBloc>(() => NotesBloc());
///
///   await flow.send(settings, ToggleViewModeEvent());
///
///   flow.expect(settings, [isUpdatingStatus(state: isGrid)]);
///   flow.expect(notes, [isUpdatingStatus(state: isGrid)]);
/// });
/// ```
///
/// The test works in steps: send (or do anything else), let the blocs go
/// idle with [JuiceFlow.send] or [JuiceFlow.settle], assert with
/// [JuiceFlow.expect], and again. No sleeps: idle is a fact the framework
/// reports, not a guess about how long a chain takes.
///
/// When the body returns, the flow closes every bloc it holds, resets
/// `BlocScope`, and FAILS the test if:
/// - a watched bloc emitted something no [JuiceFlow.expect] consumed;
/// - a send or a reaction hop was still in flight (end on
///   [JuiceFlow.send] or [JuiceFlow.settle]);
/// - a chain of reactions was refused for running past `Reaction.maxHops`;
/// - an error was recorded that no [JuiceFlow.expectErrors] claimed;
/// - anything emitted while the blocs were being closed.
///
/// A flow owns `BlocScope` for the test: it will not start while anything
/// is registered there, because the reset at its end would destroy it. One
/// flow runs at a time.
///
/// Runs on the real clock.
@isTest
void juiceFlowTest(
  String description,
  FutureOr<void> Function(JuiceFlow flow) body, {
  Object? tags,
  Object? skipTest,
}) {
  scaffolding.test(
    description,
    () => runJuiceFlow(body),
    tags: tags,
    skip: skipTest,
  );
}

/// The body of [juiceFlowTest], callable directly — from a test with its
/// own setup, or inside `testWidgets` through `tester.runAsync` (a flow
/// waits on the real clock, which `testWidgets` replaces).
Future<void> runJuiceFlow(FutureOr<void> Function(JuiceFlow flow) body) async {
  final flow = JuiceFlow._start();
  final problems = <String>[];
  try {
    await body(flow);
    problems.addAll(flow._problemsBeforeClose());
  } catch (_) {
    // The body's failure is the one to report. What closing found on top of
    // it is printed with it, not thrown over it.
    final onTop = await flow._close();
    if (onTop.isNotEmpty) {
      scaffolding
          .printOnFailure('juiceFlowTest: while closing after the failure:\n'
              '${_bullets(onTop)}');
    }
    rethrow;
  }
  problems.addAll(await flow._close());
  problems.addAll(flow._problemsAfterClose());
  if (problems.isNotEmpty) m.fail('juiceFlowTest:\n${_bullets(problems)}');
}

String _bullets(List<String> lines) => lines.map((l) => '- $l').join('\n');

/// The blocs of one [juiceFlowTest]: what the test body is handed.
final class JuiceFlow {
  JuiceFlow._(this._previousLogger) {
    _recorder = _FlowRecorder(_previousLogger);
  }

  factory JuiceFlow._start() {
    if (JuiceActivityProbe.current != null) {
      throw StateError('juiceFlowTest: a flow is already running. One flow '
          'runs at a time — it is told about every send in the process.');
    }
    if (BlocScope.hasRegistrations) {
      throw StateError('juiceFlowTest: BlocScope already holds a '
          'registration. A flow resets BlocScope when it ends, which would '
          'destroy it: register inside the flow (flow.register, or '
          'BlocScope.register in the body) and nowhere before it.');
    }
    final flow = JuiceFlow._(JuiceLoggerConfig.logger);
    JuiceLoggerConfig.configureLogger(flow._recorder);
    JuiceActivityProbe.current = flow._probe;
    return flow;
  }

  /// How long [send] and [settle] wait for the blocs to go idle before
  /// they fail.
  static const Duration defaultTimeout = Duration(seconds: 5);

  final JuiceLogger _previousLogger;
  late final _FlowRecorder _recorder;
  final _FlowProbe _probe = _FlowProbe();

  /// Watched blocs, in the order the flow was handed them.
  final Map<JuiceBloc<BlocState>, _Watch> _watched = Map.identity();
  bool _over = false;

  /// Watches [bloc], which the test built: its emissions are recorded from
  /// now on and must all be consumed by [expect]. The flow closes it when
  /// the test ends. Returns [bloc].
  ///
  /// Build the bloc inside the flow, without a `logger:` of its own: a bloc
  /// that reports its telemetry elsewhere would hide its errors from the
  /// flow, and is refused.
  ///
  /// A bloc the test does NOT hand to the flow is not recorded (its sends
  /// are still waited for).
  TBloc add<TBloc extends JuiceBloc<BlocState>>(TBloc bloc) {
    _checkRunning();
    if (_watched.containsKey(bloc)) {
      throw ArgumentError('juiceFlowTest: this ${bloc.runtimeType} is '
          'already watched');
    }
    if (bloc.isClosing) {
      throw ArgumentError('juiceFlowTest: this ${bloc.runtimeType} is '
          'closed or closing');
    }
    if (!bloc.reportsTo(_recorder)) {
      throw ArgumentError('juiceFlowTest: this ${bloc.runtimeType} does not '
          'report to the flow — it was given its own logger:, or built '
          'before the flow started — so its errors would go unseen. Build '
          'it inside the flow, without a logger.');
    }
    final watch = _Watch(typeName(bloc.runtimeType));
    watch.untap = bloc.tapEmissions((status) {
      watch.pending.add(JuiceEmission<BlocState>(
        status,
        Set<String>.of(status.event?.groupsToRebuild ?? const <String>{}),
      ));
    });
    _watched[bloc] = watch;
    return bloc;
  }

  /// Registers [TBloc] in `BlocScope` as a permanent bloc, builds it at
  /// once, and watches it as [add] does. Returns the instance — the one a
  /// reaction that names `TBloc` by type resolves.
  TBloc register<TBloc extends JuiceBloc<BlocState>>(TBloc Function() factory) {
    _checkRunning();
    BlocScope.register<TBloc>(factory, lifecycle: BlocLifecycle.permanent);
    return add(BlocScope.get<TBloc>());
  }

  /// Sends [event] to [bloc] and waits until every bloc is idle — the run
  /// it starts, every reaction that follows from it, and every run those
  /// start. Fails as [settle] fails; rethrows what the send's own future
  /// failed with (an error handler that threw). An event with no use case
  /// does not fail the send: it is recorded as an error, for
  /// [expectErrors].
  Future<void> send(
    JuiceBloc<BlocState> bloc,
    EventBase event, {
    Duration timeout = defaultTimeout,
  }) async {
    _checkRunning();
    Object? error;
    StackTrace? stackTrace;
    final sent = bloc.send(event).then<void>((_) {}, onError: (Object e, s) {
      error = e;
      stackTrace = s as StackTrace;
    });
    await settle(timeout: timeout);
    await sent;
    if (error != null) Error.throwWithStackTrace(error!, stackTrace!);
  }

  /// Waits until every bloc in the process is idle: no send in flight
  /// (waiting in a `sequential` queue counts), no reaction hop pending —
  /// and still none one turn of the event loop later.
  ///
  /// Fails the test if that has not happened within [timeout], naming what
  /// is still in flight.
  Future<void> settle({Duration timeout = defaultTimeout}) {
    _checkRunning();
    final done = Completer<void>();
    late final Timer timer;

    void check() {
      if (done.isCompleted) return;
      if (!_probe.idle) {
        _probe.onNextIdle(check);
        return;
      }
      // Idle now. A stream listener or an awaiting caller may be about to
      // send: idle counts when a whole turn passes with nothing begun.
      final seen = _probe.begun;
      Timer.run(() {
        if (done.isCompleted) return;
        if (_probe.idle && _probe.begun == seen) {
          timer.cancel();
          done.complete();
        } else {
          check();
        }
      });
    }

    timer = Timer(timeout, () {
      try {
        m.fail('juiceFlowTest: the blocs were not idle after $timeout. '
            'Still in flight: ${_probe.describeInFlight()}');
      } catch (failure, stackTrace) {
        done.completeError(failure, stackTrace);
      }
    });
    check();
    return done.future;
  }

  /// Asserts on what [bloc] emitted since its last [expect] (or since it
  /// was watched), exactly and in order, and consumes it.
  ///
  /// [expected] is one matcher (or value) per emission — [isUpdatingStatus],
  /// [isWaitingStatus], [isFailureStatus], [isCancelingStatus] — or a single
  /// matcher over the whole list. Order is asserted per bloc, not across
  /// blocs.
  void expect(JuiceBloc<BlocState> bloc, Object expected) {
    _checkRunning();
    final watch = _watched[bloc];
    if (watch == null) {
      throw ArgumentError('juiceFlowTest: this ${bloc.runtimeType} is not '
          'watched — hand it to the flow with add or register');
    }
    final emitted = List.of(watch.pending);
    watch.pending.clear();
    m.expect(emitted, asEmissionsMatcher(expected),
        reason: 'juiceFlowTest: ${watch.name} emitted $emitted');
  }

  /// Asserts on the errors recorded since the last [expectErrors], in
  /// order, and claims them: the error of every error-level telemetry entry
  /// — a use case that threw, a reaction callback that threw, a
  /// stream-binding error, an event with no use case — each once, however
  /// many entries carry it. Without it, any such error fails the test.
  ///
  /// A refused reaction chain is not an error to claim: it always fails the
  /// test.
  void expectErrors(Object expected) {
    _checkRunning();
    final errors = List.of(_recorder.errors);
    _recorder.errors.clear();
    m.expect(errors, m.wrapMatcher(expected),
        reason: 'juiceFlowTest: errors recorded');
  }

  void _checkRunning() {
    if (_over) {
      throw StateError('juiceFlowTest: this flow is over — its test ended');
    }
  }

  /// What is wrong at the end of the body, asked BEFORE anything closes.
  List<String> _problemsBeforeClose() => [
        if (!_probe.idle)
          'still in flight when the test ended: '
              '${_probe.describeInFlight()}. End on flow.send or '
              'flow.settle.',
      ];

  /// Closes everything the flow holds and hands the logger and the probe
  /// back. Never throws: what failed is returned.
  Future<List<String>> _close() async {
    _over = true;
    final problems = <String>[];
    for (final watch in _watched.values) {
      watch.untap();
    }
    _recorder.closing = true;
    // Watched instances first, last handed in first; then everything
    // registered (a registered bloc closed here is skipped there).
    for (final bloc in _watched.keys.toList().reversed) {
      try {
        await bloc.close();
      } catch (error) {
        problems.add('closing ${bloc.runtimeType} threw: $error');
      }
    }
    try {
      // `package:juice/testing.dart` is the test helper library.
      // ignore: invalid_use_of_visible_for_testing_member
      await BlocScope.reset();
    } catch (error) {
      problems.add('resetting BlocScope threw: $error');
    }
    JuiceLoggerConfig.configureLogger(_previousLogger);
    JuiceActivityProbe.current = null;
    return problems;
  }

  /// What is wrong once everything is closed.
  List<String> _problemsAfterClose() => [
        for (final watch in _watched.values)
          if (watch.pending.isNotEmpty)
            '${watch.name} emitted ${watch.pending.length} status(es) no '
                'flow.expect consumed: ${watch.pending}',
        if (_recorder.refusals.isNotEmpty)
          'a chain of reactions was refused: ${_recorder.refusals}',
        if (_recorder.errors.isNotEmpty)
          'unexpected error(s): ${_recorder.errors}. Claim them with '
              'flow.expectErrors.',
        if (_recorder.emissionsWhileClosing > 0)
          '${_recorder.emissionsWhileClosing} emission(s) dropped while '
              'the blocs were closing',
      ];
}

class _Watch {
  _Watch(this.name);
  final String name;
  final List<JuiceEmission<BlocState>> pending = [];
  late final void Function() untap;
}

/// The flow's side of [JuiceActivityProbe]: what is in flight right now.
class _FlowProbe implements JuiceActivityProbe {
  final Set<JuiceWork> _inFlight = Set.identity();
  final List<void Function()> _idleWaiters = [];

  /// How many pieces of work ever began — a turn in which this did not
  /// move began nothing.
  int begun = 0;

  bool get idle => _inFlight.isEmpty;

  void onNextIdle(void Function() callback) => _idleWaiters.add(callback);

  String describeInFlight() => _inFlight.join(', ');

  @override
  void began(JuiceWork work) {
    begun++;
    _inFlight.add(work);
  }

  @override
  void ended(JuiceWork work) {
    _inFlight.remove(work);
    if (_inFlight.isNotEmpty || _idleWaiters.isEmpty) return;
    final waiters = List.of(_idleWaiters);
    _idleWaiters.clear();
    for (final waiter in waiters) {
      waiter();
    }
  }
}

/// Forwards everything to the logger that was configured, keeping what the
/// flow asserts on.
class _FlowRecorder implements JuiceLogger {
  _FlowRecorder(this._inner);
  final JuiceLogger _inner;

  /// Unclaimed errors, each ONCE however many entries carry it: a use
  /// case that throws is recorded as `useCaseFailed` and again, by the
  /// bloc's error path, as `blocError`.
  final List<Object> errors = [];
  final Set<Object> _seen = Set.identity();
  final List<Object> refusals = [];
  bool closing = false;
  int emissionsWhileClosing = 0;

  @override
  void record(JuiceTelemetry entry) {
    if (entry.kind == JuiceTelemetryKind.reactionRefused) {
      refusals.add(entry.error ?? entry.message);
    } else if (entry.isError) {
      final error = entry.error ?? entry.message;
      if (_seen.add(error)) errors.add(error);
    } else if (closing && entry.kind == JuiceTelemetryKind.emissionAfterClose) {
      emissionsWhileClosing++;
    }
    _inner.record(entry);
  }

  @override
  void log(String message,
          {Level level = Level.info, Map<String, dynamic>? context}) =>
      _inner.log(message, level: level, context: context);

  @override
  void logError(String message, Object error, StackTrace stackTrace,
          {Map<String, dynamic>? context}) =>
      _inner.logError(message, error, stackTrace, context: context);
}
