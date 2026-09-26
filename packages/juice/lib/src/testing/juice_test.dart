import 'package:matcher/expect.dart' as m;
import 'package:logger/web.dart' show Level;
import 'package:meta/meta.dart';
import 'package:test_api/scaffolding.dart' as scaffolding;

import '../bloc/bloc.dart';

/// One status a bloc emitted during a [juiceTest], with the rebuild groups
/// it carried AT EMIT TIME — exactly what widgets' group filter saw for it.
///
/// Snapshotted at emit time because groups accumulate on the event object
/// across a multi-emit use case (AGENTS gotcha 4): reading
/// `status.event?.groupsToRebuild` after the test shows the union of EVERY
/// emit, while this shows the set as of this emission (its own groups plus
/// those of the same event's earlier emits).
@immutable
class JuiceEmission<TState extends BlocState> {
  /// Creates an emission record.
  const JuiceEmission(this.status, this.groups);

  /// The emitted status.
  final StreamStatus<TState> status;

  /// The groups widgets saw for this emission (a copy taken at emit time).
  final Set<String> groups;

  /// The emitted state.
  TState get state => status.state;

  @override
  String toString() =>
      '${status.runtimeType.toString().split('<').first}(${status.state}, '
      'groups: $groups)';
}

/// Declares a bloc test: build, (seed), act, then — with the bloc CLOSED —
/// assert on exactly what it emitted.
///
/// ```dart
/// juiceTest<CounterBloc, CounterState>(
///   'increment emits the new count on the counter group',
///   build: () => CounterBloc(),
///   act: (bloc) => bloc.send(IncrementEvent()),   // return the future
///   expect: () => [
///     isUpdatingStatus(
///       state: predicate<CounterState>((s) => s.count == 1),
///       groups: {CounterGroups.counter},
///     ),
///   ],
/// );
/// ```
///
/// No fixed sleeps: `send()` returns a future that completes when the event
/// is fully processed, so [act] returning it is enough. Use [wait] only for
/// work that outlives processing on purpose (a debounce, a timer).
///
/// - [seed] puts the bloc in a starting state (via the built-in
///   `UpdateEvent`) before recording starts; the seed emission is not
///   recorded.
/// - [expect] returns the expected emissions, one matcher (or value) per
///   emission, in order — use [isUpdatingStatus], [isWaitingStatus],
///   [isFailureStatus], [isCancelingStatus]. [skip] drops that many leading
///   emissions first.
/// - [errors] returns the expected use-case errors (the `use_case_error`
///   spans, in order). Without it, any use-case error fails the test.
/// - [verify] runs last, with the closed bloc, for further checks.
/// - The bloc is closed BEFORE asserting. The test fails if a use case was
///   still running when the bloc closed (a telemetry START without its END —
///   typically an [act] that didn't return the `send()` future), or if
///   anything emitted during the close. Opt out with
///   `allowInFlightAtClose: true`. Fire-and-forget work a use case left
///   behind (a bare timer) can't be observed; its emit is dropped by the
///   close fence.
@isTest
void juiceTest<TBloc extends JuiceBloc<TState>, TState extends BlocState>(
  String description, {
  required TBloc Function() build,
  TState Function()? seed,
  FutureOr<void> Function(TBloc bloc)? act,
  Duration? wait,
  int skip = 0,
  Object Function()? expect,
  Object Function()? errors,
  FutureOr<void> Function(TBloc bloc)? verify,
  bool allowInFlightAtClose = false,
  Object? tags,
  Object? skipTest,
}) {
  scaffolding.test(
    description,
    () => runJuiceTest<TBloc, TState>(
      build: build,
      seed: seed,
      act: act,
      wait: wait,
      skip: skip,
      expect: expect,
      errors: errors,
      verify: verify,
      allowInFlightAtClose: allowInFlightAtClose,
    ),
    tags: tags,
    skip: skipTest,
  );
}

/// The body of [juiceTest], callable directly (e.g. inside `testWidgets`, or
/// a test with custom setup). Returns the recorded emissions.
Future<List<JuiceEmission<TState>>>
    runJuiceTest<TBloc extends JuiceBloc<TState>, TState extends BlocState>({
  required TBloc Function() build,
  TState Function()? seed,
  FutureOr<void> Function(TBloc bloc)? act,
  Duration? wait,
  int skip = 0,
  Object Function()? expect,
  Object Function()? errors,
  FutureOr<void> Function(TBloc bloc)? verify,
  bool allowInFlightAtClose = false,
}) async {
  final previousLogger = JuiceLoggerConfig.logger;
  final recorder = _RecordingLogger(previousLogger);
  JuiceLoggerConfig.configureLogger(recorder);

  final emissions = <JuiceEmission<TState>>[];
  void Function()? untap;
  var inFlightAtClose = 0;
  late final TBloc bloc;
  try {
    bloc = build();
    if (seed != null) {
      await bloc.send(UpdateEvent<TState>(newState: seed()));
    }
    // Recording starts after the seed.
    recorder.useCaseErrors.clear();
    untap = bloc.tapEmissions((status) {
      emissions.add(JuiceEmission<TState>(
        status,
        Set<String>.of(status.event?.groupsToRebuild ?? const <String>{}),
      ));
    });

    if (act != null) await act(bloc);
    if (wait != null) await Future<void>.delayed(wait);
  } finally {
    untap?.call();
    inFlightAtClose = recorder.openSpans.length;
    // Close BEFORE asserting: nothing emitted from here on can leak into
    // another test; in-flight work and late emissions are reported below.
    try {
      await bloc.close();
    } finally {
      JuiceLoggerConfig.configureLogger(previousLogger);
    }
  }

  final recorded = emissions.skip(skip).toList();
  if (expect != null) {
    final expected = expect();
    m.expect(recorded, _asEmissionsMatcher(expected),
        reason: 'juiceTest: emitted $recorded');
  }

  if (errors != null) {
    m.expect(recorder.useCaseErrors, m.wrapMatcher(errors()),
        reason: 'juiceTest: use-case errors');
  } else if (recorder.useCaseErrors.isNotEmpty) {
    m.fail('juiceTest: unexpected use-case error(s): '
        '${recorder.useCaseErrors}. Pass `errors:` to expect them.');
  }

  if (!allowInFlightAtClose &&
      (inFlightAtClose > 0 || recorder.emissionsAfterClose > 0)) {
    m.fail('juiceTest: $inFlightAtClose use case(s) still running when the '
        'bloc closed (${recorder.emissionsAfterClose} emission(s) dropped '
        'after close). Return the send() future from act, add `wait:`, or '
        'pass `allowInFlightAtClose: true`.');
  }

  if (verify != null) await verify(bloc);
  return emissions;
}

m.Matcher _asEmissionsMatcher(Object expected) {
  if (expected is m.Matcher) return expected;
  if (expected is Iterable) {
    return m
        .orderedEquals(expected.map((e) => e is m.Matcher ? e : m.equals(e)));
  }
  return m.wrapMatcher(expected);
}

/// Matches a [JuiceEmission] whose status is an [UpdatingStatus].
///
/// [state] and [groups] are optional; each is a value (compared with `==`)
/// or a `Matcher`. [groups] is compared to the emission's groups as widgets
/// saw them (see [JuiceEmission.groups]).
m.Matcher isUpdatingStatus({Object? state, Object? groups}) =>
    _EmissionMatcher<UpdatingStatus>('UpdatingStatus', state, groups, null);

/// Matches a [JuiceEmission] whose status is a [WaitingStatus].
m.Matcher isWaitingStatus({Object? state, Object? groups}) =>
    _EmissionMatcher<WaitingStatus>('WaitingStatus', state, groups, null);

/// Matches a [JuiceEmission] whose status is a [FailureStatus]; [error]
/// matches the status's error.
m.Matcher isFailureStatus({Object? state, Object? groups, Object? error}) =>
    _EmissionMatcher<FailureStatus>('FailureStatus', state, groups, error);

/// Matches a [JuiceEmission] whose status is a [CancelingStatus].
m.Matcher isCancelingStatus({Object? state, Object? groups}) =>
    _EmissionMatcher<CancelingStatus>('CancelingStatus', state, groups, null);

class _EmissionMatcher<S> extends m.Matcher {
  _EmissionMatcher(this.kind, Object? state, Object? groups, Object? error)
      : _state = state == null ? null : m.wrapMatcher(state),
        _groups = groups == null
            ? null
            : groups is m.Matcher
                ? groups
                : m.equals(groups),
        _error = error == null ? null : m.wrapMatcher(error);

  final String kind;
  final m.Matcher? _state;
  final m.Matcher? _groups;
  final m.Matcher? _error;

  @override
  bool matches(Object? item, Map matchState) {
    if (item is! JuiceEmission) return false;
    if (item.status is! S) return false;
    if (_state != null && !_state.matches(item.status.state, matchState)) {
      return false;
    }
    if (_groups != null && !_groups.matches(item.groups, matchState)) {
      return false;
    }
    if (_error != null) {
      final status = item.status;
      final err = status is FailureStatus ? status.error : null;
      if (!_error.matches(err, matchState)) return false;
    }
    return true;
  }

  @override
  m.Description describe(m.Description description) {
    description.add(kind);
    if (_state != null) {
      description.add(' with state ').addDescriptionOf(_state);
    }
    if (_groups != null) {
      description.add(' on groups ').addDescriptionOf(_groups);
    }
    if (_error != null) {
      description.add(' with error ').addDescriptionOf(_error);
    }
    return description;
  }
}

/// Forwards everything to the app's logger while counting what juiceTest
/// asserts on: use-case error spans and emissions after close.
class _RecordingLogger implements JuiceLogger {
  _RecordingLogger(this._inner);
  final JuiceLogger _inner;

  final useCaseErrors = <Object>[];
  final openSpans = <Object?>{};
  int emissionsAfterClose = 0;

  @override
  void log(String message,
      {Level level = Level.info, Map<String, dynamic>? context}) {
    switch (context?['type']) {
      case 'emission_after_close':
        emissionsAfterClose++;
      case 'use_case_execution':
        openSpans.add(context!['executionId']);
      case 'use_case_completed':
        openSpans.remove(context!['executionId']);
    }
    _inner.log(message, level: level, context: context);
  }

  @override
  void logError(String message, Object error, StackTrace stackTrace,
      {Map<String, dynamic>? context}) {
    // The executor's span-closer carries executionId; BlocErrorHandler's
    // summary shares the type without it (AGENTS §4b) — count each error once.
    if (context?['type'] == 'use_case_error' &&
        context!.containsKey('executionId')) {
      useCaseErrors.add(error);
      openSpans.remove(context['executionId']);
    }
    _inner.logError(message, error, stackTrace, context: context);
  }
}
