// ignore_for_file: implementation_imports, invalid_use_of_internal_member
import 'package:juice/juice.dart';
import 'package:juice/src/bloc/src/core/state_manager.dart';
import 'package:juice/src/bloc/src/core/status_emitter.dart';
import 'package:juice/src/bloc/src/core/type_names.dart';

import 'dispatch.dart' show SilentJuiceLogger;
import 'stats.dart';

/// WHERE A JUICE DISPATCH'S TIME GOES — measured layer by layer.
///
/// Rows of kind `real` time a Juice send path end to end:
/// - `stateManager.emit` — the raw store (set + broadcast add);
/// - `statusEmitter.emitUpdate` — the store plus the status object, the
///   group merge and the emission's telemetry record;
/// - `send · …` — the full path: a reused use-case instance
///   (StatefulUseCaseBuilder) or a fresh one per event (UseCaseBuilder),
///   with the chatter built (silent logger) or not built (telemetry floor
///   at warning; the default logger in release), registered restartable,
///   and in the burst shape at two sizes.
///
/// Rows of kind `synthetic` time ONE piece alone — real framework code or a
/// stand-in — so a send's cost can be decomposed: the three telemetry
/// entries as the context maps 1.x built and as the records 2.0.0 builds;
/// `Type.toString()` against the `typeName` memo; a Stopwatch; the context
/// object with the closures the executor wires; the group-set spread; a
/// zone lookup; the widgets' group filter in its allocating and its
/// allocation-free form; two and four nested awaited async calls (a send
/// awaits twice: the executor and the use case; four was the 1.x depth).
///
/// Every product of a synthetic row escapes through [_consume], a
/// never-inlined call, so the compiler cannot elide the work. The burst
/// rows fire the same ops without awaiting each one: a cost that grows with
/// the size is depth (microtask queue, allocation, GC), a flat one is per
/// event. Silent logger throughout, µs per operation, every round kept.

class _S extends BlocState {
  const _S(this.n);
  final int n;
}

class _Ev extends EventBase {}

class _UC extends BlocUseCase<_FreshBloc, _Ev> {
  @override
  Future<void> execute(_Ev e) async =>
      emitUpdate(newState: _S(bloc.state.n + 1), groupsToRebuild: {'g'});
}

class _StatefulUC extends BlocUseCase<_StatefulBloc, _Ev> {
  @override
  Future<void> execute(_Ev e) async =>
      emitUpdate(newState: _S(bloc.state.n + 1), groupsToRebuild: {'g'});
}

class _FreshBloc extends JuiceBloc<_S> {
  _FreshBloc()
    : super(const _S(0), [
        () => UseCaseBuilder.typed(
          () => _UC(),
          concurrency: EventConcurrency.concurrent,
        ),
      ]);
}

class _RestartableUC extends BlocUseCase<_RestartableBloc, _Ev> {
  @override
  Future<void> execute(_Ev e) async =>
      emitUpdate(newState: _S(bloc.state.n + 1), groupsToRebuild: {'g'});
}

class _RestartableBloc extends JuiceBloc<_S> {
  _RestartableBloc()
    : super(const _S(0), [
        () => UseCaseBuilder.typed(
          () => _RestartableUC(),
          concurrency: EventConcurrency.restartable,
        ),
      ]);
}

class _StatefulBloc extends JuiceBloc<_S> {
  _StatefulBloc()
    : super(const _S(0), [
        () => StatefulUseCaseBuilder(
          typeOfEvent: _Ev,
          useCaseGenerator: () => _StatefulUC(),
          concurrency: EventConcurrency.concurrent,
        ),
      ]);
}

/// `real`: a Juice send path timed end to end. `synthetic`: one piece timed
/// alone — real framework code or a stand-in.
enum RowKind { real, synthetic }

class BreakdownRow {
  BreakdownRow(this.layer, this.kind, this.micros);
  final String layer;
  final RowKind kind;
  final double micros;
}

/// A layer's rounds gathered: median, range, spread.
class BreakdownResult {
  BreakdownResult(this.layer, this.kind, this.sample);
  final String layer;
  final RowKind kind;
  final Sample sample;
  Map<String, Object> toJson() => {
    'layer': layer,
    'kind': kind.name,
    ...sample.toJson('microsPerOp'),
  };
}

/// Stand-in for the per-execution part of UseCaseContext: the four emit
/// closures that capture the event (emitEvent and navigate are shared per
/// bloc).
class _SyntheticContext {
  _SyntheticContext(this.update, this.waiting, this.failure, this.cancel);
  final void Function(Object?, Object?) update;
  final void Function(Object?, Object?) waiting;
  final void Function(Object?, Object?) failure;
  final void Function(Object?, Object?) cancel;
}

/// Stand-in for a UseCase: the function fields the executor assigns per
/// execution (five closures; `navigate` is the context's shared closure).
class _SyntheticUseCase {
  late void Function({Object? a, Object? b}) emitUpdate;
  late void Function({Object? a, Object? b}) emitWaiting;
  late void Function({Object? a, Object? b}) emitFailure;
  late void Function({Object? a, Object? b}) emitCancel;
  late void Function({Object? a}) emitEvent;
  late void Function(Object?, Object?) navigate;
}

/// The sink every synthetic product escapes through: never inlined, so the
/// value must exist. Returns a hash the caller SUMS into a checksum (an XOR
/// cancels when the same object comes back twice, as a cached type name
/// does).
@pragma('vm:never-inline')
int _consume(Object? value) => identityHashCode(value);

/// Runs [body] with the framework's telemetry floor at [level], restoring
/// the previous floor whatever happens.
Future<T> _withMinLevel<T>(Level level, Future<T> Function() body) async {
  final saved = JuiceLoggerConfig.minLevel;
  JuiceLoggerConfig.minLevel = level;
  try {
    return await body();
  } finally {
    JuiceLoggerConfig.minLevel = saved;
  }
}

/// Runs [body] with [logger] configured, restoring the previous logger
/// whatever happens.
Future<T> _withLogger<T>(JuiceLogger logger, Future<T> Function() body) async {
  final saved = JuiceLoggerConfig.logger;
  JuiceLoggerConfig.configureLogger(logger);
  try {
    return await body();
  } finally {
    JuiceLoggerConfig.configureLogger(saved);
  }
}

/// Times [n] awaited sends on a fresh [bloc], proves every one ran, then
/// closes it. A superseded restartable run emits nothing, so [expectAll]
/// is false for the restartable row.
Future<double> _sends(
  JuiceBloc<_S> bloc,
  int n, {
  bool expectAll = true,
}) async {
  try {
    final micros = await _timeAsync(n, (_) => bloc.send(_Ev()));
    if (expectAll && bloc.state.n != n) {
      throw StateError('${bloc.runtimeType}: ${bloc.state.n} of $n sends ran');
    }
    return micros;
  } finally {
    await bloc.close();
  }
}

/// The burst shape of [_sends].
Future<double> _burst(JuiceBloc<_S> bloc, int n) async {
  try {
    return await _timeBurst(n, (_) => bloc.send(_Ev()));
  } finally {
    await bloc.close();
  }
}

Future<double> _timeAsync(int n, Future<void> Function(int i) op) async {
  final sw = Stopwatch()..start();
  for (var i = 0; i < n; i++) {
    await op(i);
  }
  sw.stop();
  return sw.elapsedMicroseconds / n;
}

/// Fire every op, await only the last (the dispatch benchmark's burst).
Future<double> _timeBurst(int n, Future<void> Function(int i) op) async {
  final sw = Stopwatch()..start();
  Future<void>? last;
  for (var i = 0; i < n; i++) {
    last = op(i);
  }
  await last;
  sw.stop();
  return sw.elapsedMicroseconds / n;
}

double _timeSync(int n, void Function(int i) op) {
  final sw = Stopwatch()..start();
  for (var i = 0; i < n; i++) {
    op(i);
  }
  sw.stop();
  return sw.elapsedMicroseconds / n;
}

// Nested awaited async calls: four was the 1.x send depth, two is 2.0.0's
// (the executor's await and the use case's own).
Future<void> _hop4(int i) => _hop3(i);
Future<void> _hop3(int i) async => await _hop2(i);
Future<void> _hop2(int i) async => await _hop1(i);
Future<void> _hop1(int i) async => await _hop0(i);
Future<void> _hop0(int i) async {}

Future<List<BreakdownRow>> _once(int n) async {
  final rows = <BreakdownRow>[];
  void add(String layer, RowKind kind, double micros) =>
      rows.add(BreakdownRow(layer, kind, micros));

  /// A synthetic row's checksum is a sum of identity hashes over n
  /// iterations: zero means the loop body produced nothing the sink saw.
  void check(String layer, int checksum) {
    if (checksum == 0) throw StateError('$layer: nothing reached the sink');
  }

  // --- the store and the emitter
  final sm = StateManager<StreamStatus<_S>>(
    StreamStatus.updating(const _S(0), const _S(0), null),
  );
  final sub = sm.stream.listen((_) {});
  add(
    'stateManager.emit',
    RowKind.real,
    _timeSync(n, (i) {
      sm.emit(StreamStatus.updating(_S(i), const _S(0), null));
    }),
  );
  await Future<void>.delayed(Duration.zero);
  final emitter = StatusEmitter<_S>(
    stateManager: sm,
    logger: SilentJuiceLogger(),
    blocName: '_FreshBloc',
  );
  add(
    'statusEmitter.emitUpdate',
    RowKind.real,
    _timeSync(n, (i) {
      emitter.emitUpdate(_Ev(), _S(i), {'g'});
    }),
  );
  await Future<void>.delayed(Duration.zero);
  await sub.cancel();
  await sm.close();

  // --- the three telemetry entries of a send: as the maps 1.x built, and
  //     as the records 2.0.0 builds.
  final uc = _UC();
  final ev = _Ev();
  var sum = 0;
  add(
    'telemetry maps (3 per event)',
    RowKind.synthetic,
    _timeSync(n, (i) {
      final useCaseName = uc.runtimeType.toString();
      final eventName = ev.runtimeType.toString();
      sum += _consume({
        'type': 'use_case_execution',
        'useCase': useCaseName,
        'event': eventName,
        'executionId': i,
      });
      sum += _consume({
        'type': 'state_emission',
        'status': 'update',
        'state': i,
        'bloc': '_FreshBloc',
        'groups': const {'g'},
        'event': eventName,
      });
      sum += _consume({
        'type': 'use_case_completed',
        'useCase': useCaseName,
        'event': eventName,
        'executionId': i,
        'elapsedMicros': i,
      });
    }),
  );
  check('telemetry maps', sum);
  sum = 0;
  add(
    'telemetry records (3 per event)',
    RowKind.synthetic,
    _timeSync(n, (i) {
      final useCaseName = typeName(uc.runtimeType);
      final eventName = typeName(ev.runtimeType);
      sum += _consume(
        JuiceTelemetry(
          JuiceTelemetryKind.useCaseStarted,
          useCase: useCaseName,
          event: eventName,
          executionId: i,
        ),
      );
      sum += _consume(
        JuiceTelemetry(
          JuiceTelemetryKind.stateEmitted,
          status: EmissionKind.update,
          state: i,
          bloc: '_FreshBloc',
          groups: const {'g'},
          event: eventName,
        ),
      );
      sum += _consume(
        JuiceTelemetry(
          JuiceTelemetryKind.useCaseCompleted,
          useCase: useCaseName,
          event: eventName,
          executionId: i,
          elapsedMicros: i,
        ),
      );
    }),
  );
  check('telemetry records', sum);

  // --- the pieces a send allocates or looks up, each alone.
  sum = 0;
  add(
    'Type.toString() ×3',
    RowKind.synthetic,
    _timeSync(n, (i) {
      sum += _consume(ev.runtimeType.toString());
      sum += _consume(uc.runtimeType.toString());
      sum += _consume(uc.runtimeType.toString());
    }),
  );
  check('Type.toString()', sum);
  sum = 0;
  add(
    'typeName() memo ×3',
    RowKind.synthetic,
    _timeSync(n, (i) {
      sum += _consume(typeName(ev.runtimeType));
      sum += _consume(typeName(uc.runtimeType));
      sum += _consume(typeName(uc.runtimeType));
    }),
  );
  check('typeName()', sum);
  sum = 0;
  add(
    'Stopwatch()..start',
    RowKind.synthetic,
    _timeSync(n, (i) {
      sum += _consume(Stopwatch()..start());
    }),
  );
  check('Stopwatch', sum);
  sum = 0;
  add(
    'context object + 9 wiring closures',
    RowKind.synthetic,
    _timeSync(n, (i) {
      final ctx = _SyntheticContext(
        (a, b) => sum += 1,
        (a, b) => sum += 2,
        (a, b) => sum += 4,
        (a, b) => sum += 8,
      );
      final u = _SyntheticUseCase();
      u.emitUpdate = ({a, b}) {
        ctx.update(a, b);
      };
      u.emitWaiting = ({a, b}) {
        ctx.waiting(a, b);
      };
      u.emitFailure = ({a, b}) {
        ctx.failure(a, b);
      };
      u.emitCancel = ({a, b}) {
        ctx.cancel(a, b);
      };
      u.emitEvent = ({a}) {
        sum += 16;
      };
      u.navigate = _sharedNavigate;
      sum += _consume(ctx) + _consume(u);
    }),
  );
  check('context + closures', sum);
  final eventGroups = <String>{'cell:7'};
  const widgetGroups = {'g'};
  sum = 0;
  add(
    'group set spread {...a, ...b}',
    RowKind.synthetic,
    _timeSync(n, (i) {
      sum += _consume({...eventGroups, ...widgetGroups});
    }),
  );
  check('set spread', sum);
  sum = 0;
  add(
    'Zone.current[key] lookup',
    RowKind.synthetic,
    _timeSync(n, (i) {
      sum += _consume(Zone.current[#juice.bench]) + 1;
    }),
  );
  check('zone lookup', sum);

  // --- the widgets' group filter per emission per widget: a one-element
  //     event set against a one-element widget set, as the cells scenario
  //     runs it 1,000 times per emission.
  var hits = 0;
  add(
    'group filter · intersection().isNotEmpty',
    RowKind.synthetic,
    _timeSync(n, (i) {
      if (eventGroups.intersection(widgetGroups).isNotEmpty) hits++;
    }),
  );
  add(
    'group filter · any(contains)',
    RowKind.synthetic,
    _timeSync(n, (i) {
      if (eventGroups.any(widgetGroups.contains)) hits++;
    }),
  );
  if (hits != 0) throw StateError('disjoint sets matched');

  // --- awaited async depth alone.
  add('2 awaited async hops', RowKind.synthetic, await _timeAsync(n, _hop2));
  add('4 awaited async hops', RowKind.synthetic, await _timeAsync(n, _hop4));

  // --- the full send, every form.
  add(
    'send · StatefulUseCaseBuilder (reused instance)',
    RowKind.real,
    await _sends(_StatefulBloc(), n),
  );
  add(
    'send · UseCaseBuilder (fresh instance)',
    RowKind.real,
    await _sends(_FreshBloc(), n),
  );
  add(
    'send · fresh instance, minLevel = warning (chatter not built)',
    RowKind.real,
    await _withMinLevel(Level.warning, () => _sends(_FreshBloc(), n)),
  );
  // DefaultJuiceLogger declares what its filter keeps — nothing outside
  // debug — so in a release build this row lands on the one above with no
  // knob set.
  add(
    'send · fresh instance, DefaultJuiceLogger, no knob set',
    RowKind.real,
    await _withLogger(DefaultJuiceLogger(), () => _sends(_FreshBloc(), n)),
  );
  // The restartable mode's own cost: a zone fork per send plus the per-run
  // token.
  add(
    'send · fresh instance, restartable, minLevel = warning',
    RowKind.real,
    await _withMinLevel(
      Level.warning,
      () => _sends(_RestartableBloc(), n, expectAll: false),
    ),
  );

  // --- burst shape, two sizes.
  for (final size in [n ~/ 10, n]) {
    add(
      '4 awaited async hops · burst n=$size',
      RowKind.synthetic,
      await _timeBurst(size, _hop4),
    );
    add(
      'send · fresh instance · burst n=$size',
      RowKind.real,
      await _burst(_FreshBloc(), size),
    );
    add(
      'send · reused instance · burst n=$size',
      RowKind.real,
      await _burst(_StatefulBloc(), size),
    );
    add(
      'send · fresh, minLevel = warning · burst n=$size',
      RowKind.real,
      await _withMinLevel(Level.warning, () => _burst(_FreshBloc(), size)),
    );
  }

  return rows;
}

void _sharedNavigate(Object? a, Object? b) {}

/// Warm-up, then EVERY round per layer (median + range in the report).
Future<List<BreakdownResult>> runBreakdown({int n = 20000, int rounds = 5}) =>
    _withLogger(SilentJuiceLogger(), () async {
      await _once(n);
      final all = <String, (RowKind, List<double>)>{};
      for (var r = 0; r < rounds; r++) {
        for (final row in await _once(n)) {
          all.putIfAbsent(row.layer, () => (row.kind, [])).$2.add(row.micros);
        }
      }
      return [
        for (final e in all.entries)
          BreakdownResult(e.key, e.value.$1, Sample(e.value.$2)),
      ];
    });
