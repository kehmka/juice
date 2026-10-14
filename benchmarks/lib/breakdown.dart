// ignore_for_file: implementation_imports, invalid_use_of_internal_member
import 'package:juice/juice.dart';
import 'package:juice/src/bloc/src/core/state_manager.dart';
import 'package:juice/src/bloc/src/core/status_emitter.dart';
import 'package:juice/src/bloc/src/core/type_names.dart';

import 'dispatch.dart' show SilentJuiceLogger;
import 'stats.dart';

/// WHERE A JUICE DISPATCH'S TIME GOES — measured layer by layer.
///
/// Real Juice code, timed directly:
/// - `stateManager.emit`   — the raw state store (set + broadcast add);
/// - `statusEmitter.emit`  — + status object, group merge, emission log map;
/// - `send (stateful)`     — the full path with ONE reused use-case instance
///                           (StatefulUseCaseBuilder);
/// - `send (fresh)`        — the full path as normally registered: a fresh
///                           use-case instance per event (UseCaseBuilder).
///
/// Synthetic, labelled as such (Juice can't switch these off to compare):
/// - `telemetry maps`      — building the three context maps one event logs
///                           (span start, emission, span end) + the two type
///                           names, with nothing consuming them;
/// - `4 async hops`        — four nested awaited async calls: the 1.x send
///                           depth (send → dispatcher → executor →
///                           execute()). A send now awaits once, so this
///                           row is the reference the send rows are read
///                           against, not their model.
///
/// BURST shape: the dispatch benchmark found Juice's burst (fire all, await
/// the last) SLOWER per event than its sequential shape, on every machine,
/// while bloc and Riverpod get cheaper in burst. These rows fire the same
/// ops without awaiting each one, at two sizes: a cost that grows with the
/// size is depth (microtask queue, allocation/GC), a flat one is per event.
///
/// All with the silent logger, µs per operation, every round kept.

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

/// Whether a row times real Juice code or a synthetic stand-in.
enum RowKind { real, synthetic }

/// Stand-in for UseCaseContext: one object holding six closures.
class _SyntheticContext {
  _SyntheticContext(this.u, this.w, this.f, this.c, this.e, this.nav);
  final void Function(Object?, Object?) u;
  final void Function(Object?, Object?) w;
  final void Function(Object?, Object?) f;
  final void Function(Object?, Object?) c;
  final void Function(Object?) e;
  final void Function(Object?, Object?) nav;
}

/// Stand-in for a UseCase: the late function fields the executor wires.
class _SyntheticUseCase {
  late void Function({Object? a, Object? b}) emitUpdate;
  late void Function({Object? a, Object? b}) emitWaiting;
  late void Function({Object? a, Object? b}) emitFailure;
  late void Function({Object? a, Object? b}) emitCancel;
  late void Function({Object? a}) emitEvent;
  late void Function(Object?, Object?) navigate;
}

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
  final micros = await _timeAsync(n, (_) => bloc.send(_Ev()));
  if (expectAll && bloc.state.n != n) {
    throw StateError('${bloc.runtimeType}: ${bloc.state.n} of $n sends ran');
  }
  await bloc.close();
  return micros;
}

/// The burst shape of [_sends].
Future<double> _burst(JuiceBloc<_S> bloc, int n) async {
  final micros = await _timeBurst(n, (_) => bloc.send(_Ev()));
  await bloc.close();
  return micros;
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

// Four nested awaited async calls — the hop depth of a Juice send.
Future<void> _hop4(int i) => _hop3(i);
Future<void> _hop3(int i) async => await _hop2(i);
Future<void> _hop2(int i) async => await _hop1(i);
Future<void> _hop1(int i) async => await _hop0(i);
Future<void> _hop0(int i) async {}

Future<List<BreakdownRow>> _once(int n) async {
  final rows = <BreakdownRow>[];

  // 1. Raw state store.
  final sm = StateManager<StreamStatus<_S>>(
    StreamStatus.updating(const _S(0), const _S(0), null),
  );
  final sub = sm.stream.listen((_) {});
  rows.add(
    BreakdownRow(
      'stateManager.emit',
      RowKind.real,
      _timeSync(n, (i) {
        sm.emit(StreamStatus.updating(_S(i), const _S(0), null));
      }),
    ),
  );
  await Future<void>.delayed(Duration.zero);

  // 2. Status emitter (status + group merge + emission log map).
  final emitter = StatusEmitter<_S>(
    stateManager: sm,
    logger: SilentJuiceLogger(),
    blocName: '_FreshBloc',
  );
  rows.add(
    BreakdownRow(
      'statusEmitter.emitUpdate',
      RowKind.real,
      _timeSync(n, (i) {
        emitter.emitUpdate(_Ev(), _S(i), {'g'});
      }),
    ),
  );
  await Future<void>.delayed(Duration.zero);
  await sub.cancel();
  await sm.close();

  // 3. Telemetry maps alone (synthetic). The maps are consumed (their key
  //    counts summed and checked) so the compiler cannot drop them.
  final uc = _UC();
  final ev = _Ev();
  var keys = 0;
  rows.add(
    BreakdownRow(
      'telemetry maps (3 per event)',
      RowKind.synthetic,
      _timeSync(n, (i) {
        final useCaseName = uc.runtimeType.toString();
        final eventName = ev.runtimeType.toString();
        final start = {
          'type': 'use_case_execution',
          'useCase': useCaseName,
          'event': eventName,
          'executionId': i,
        };
        final emission = {
          'type': 'state_emission',
          'status': 'update',
          'state': i,
          'bloc': '_FreshBloc',
          'groups': const {'g'},
          'event': eventName,
        };
        final end = {
          'type': 'use_case_completed',
          'useCase': useCaseName,
          'event': eventName,
          'executionId': i,
          'elapsedMicros': i,
        };
        keys += start.length + emission.length + end.length;
      }),
    ),
  );
  if (keys != n * 15) {
    throw StateError('the synthetic maps were not built: $keys keys');
  }

  // 3a. The same three entries as typed records (what 2.0.0 builds): one
  //     object each, no map, names from the memo.
  var ids = 0;
  rows.add(
    BreakdownRow(
      'telemetry records (3 per event)',
      RowKind.synthetic,
      _timeSync(n, (i) {
        final useCaseName = typeName(uc.runtimeType);
        final eventName = typeName(ev.runtimeType);
        final start = JuiceTelemetry(
          JuiceTelemetryKind.useCaseStarted,
          useCase: useCaseName,
          event: eventName,
          executionId: i,
        );
        final emission = JuiceTelemetry(
          JuiceTelemetryKind.stateEmitted,
          status: 'update',
          state: i,
          bloc: '_FreshBloc',
          groups: const {'g'},
          event: eventName,
        );
        final end = JuiceTelemetry(
          JuiceTelemetryKind.useCaseCompleted,
          useCase: useCaseName,
          event: eventName,
          executionId: i,
          elapsedMicros: i,
        );
        ids += start.executionId! + end.executionId! + (emission.state as int);
      }),
    ),
  );
  if (ids == 0 && n > 1) throw StateError('the records were not built');

  // 3b. The per-send allocations the send path makes besides the maps
  //     (synthetic, each alone): the three Type.toString() calls (event
  //     name, use-case name in the executor, use-case name in BlocUseCase's
  //     constructor); a Stopwatch; the context object plus the eleven
  //     closures that wire a use case; the group-set copy an emit makes;
  //     and a Zone value lookup.
  var names = 0;
  rows.add(
    BreakdownRow(
      'Type.toString() ×3',
      RowKind.synthetic,
      _timeSync(n, (i) {
        names +=
            ev.runtimeType.toString().length +
            uc.runtimeType.toString().length +
            uc.runtimeType.toString().length;
      }),
    ),
  );
  if (names == 0) throw StateError('names not built');
  var memo = 0;
  rows.add(
    BreakdownRow(
      'typeName() memo ×3',
      RowKind.synthetic,
      _timeSync(n, (i) {
        memo +=
            typeName(ev.runtimeType).length +
            typeName(uc.runtimeType).length +
            typeName(uc.runtimeType).length;
      }),
    ),
  );
  if (memo != names) throw StateError('memo disagrees with toString');
  var ticks = 0;
  rows.add(
    BreakdownRow(
      'Stopwatch()..start',
      RowKind.synthetic,
      _timeSync(n, (i) {
        final sw = Stopwatch()..start();
        ticks += sw.elapsedMicroseconds;
      }),
    ),
  );
  if (ticks < 0) throw StateError('unreachable');
  var wired = 0;
  rows.add(
    BreakdownRow(
      'context object + 11 wiring closures',
      RowKind.synthetic,
      _timeSync(n, (i) {
        final ctx = _SyntheticContext(
          (a, b) => wired++,
          (a, b) => wired++,
          (a, b) => wired++,
          (a, b) => wired++,
          (a) => wired++,
          (a, b) => wired++,
        );
        final u = _SyntheticUseCase();
        u.emitUpdate = ({a, b}) {
          ctx.u(a, b);
        };
        u.emitWaiting = ({a, b}) {
          ctx.w(a, b);
        };
        u.emitFailure = ({a, b}) {
          ctx.f(a, b);
        };
        u.emitCancel = ({a, b}) {
          ctx.c(a, b);
        };
        u.emitEvent = ({a}) {
          ctx.e(a);
        };
        u.navigate = ctx.nav;
        wired += identityHashCode(u);
      }),
    ),
  );
  if (wired == 0) throw StateError('closures not built');
  final eventGroups = <String>{'cell:7'};
  const widgetGroups = {'g'};
  var merged = 0;
  rows.add(
    BreakdownRow(
      'group set spread {...a, ...b}',
      RowKind.synthetic,
      _timeSync(n, (i) {
        merged += {...eventGroups, ...widgetGroups}.length;
      }),
    ),
  );
  if (merged != n * 2) throw StateError('sets not built');
  var zones = 0;
  rows.add(
    BreakdownRow(
      'Zone.current[key] lookup',
      RowKind.synthetic,
      _timeSync(n, (i) {
        if (Zone.current[#juice.bench] == null) zones++;
      }),
    ),
  );
  if (zones != n) throw StateError('zone lookups skipped');

  // 3c. The widget filter per emission per widget: a 1-element event set
  //     against a 1-element widget set, as the cells scenario runs it 1,000
  //     times per emission — the allocating form and the allocation-free one.
  var hits = 0;
  rows.add(
    BreakdownRow(
      'group filter · intersection().isNotEmpty',
      RowKind.synthetic,
      _timeSync(n, (i) {
        if (eventGroups.intersection(widgetGroups).isNotEmpty) hits++;
      }),
    ),
  );
  rows.add(
    BreakdownRow(
      'group filter · any(contains)',
      RowKind.synthetic,
      _timeSync(n, (i) {
        if (eventGroups.any(widgetGroups.contains)) hits++;
      }),
    ),
  );
  if (hits != 0) throw StateError('disjoint sets matched');

  // 4. Async hop depth alone (synthetic).
  rows.add(
    BreakdownRow(
      '4 awaited async hops',
      RowKind.synthetic,
      await _timeAsync(n, _hop4),
    ),
  );

  // 5. Full send, one reused use-case instance.
  rows.add(
    BreakdownRow(
      'send · StatefulUseCaseBuilder (reused instance)',
      RowKind.real,
      await _sends(_StatefulBloc(), n),
    ),
  );

  // 6. Full send, fresh instance per event (the normal registration).
  rows.add(
    BreakdownRow(
      'send · UseCaseBuilder (fresh instance)',
      RowKind.real,
      await _sends(_FreshBloc(), n),
    ),
  );

  // 7. The same send with the framework's chatter NOT BUILT
  //    (JuiceLoggerConfig.minLevel = Level.warning) — the one knob the
  //    breakdown priced.
  rows.add(
    BreakdownRow(
      'send · fresh instance, minLevel = warning (chatter not built)',
      RowKind.real,
      await _withMinLevel(Level.warning, () => _sends(_FreshBloc(), n)),
    ),
  );

  // 7b. The same send with NOTHING configured but the default logger:
  //     DefaultJuiceLogger declares what its filter keeps — nothing outside
  //     debug — so in a release build this row should land on row 7 with
  //     no knob set.
  rows.add(
    BreakdownRow(
      'send · fresh instance, DefaultJuiceLogger, no knob set',
      RowKind.real,
      await _withLogger(DefaultJuiceLogger(), () => _sends(_FreshBloc(), n)),
    ),
  );

  // 7c. The restartable mode's own cost: a zone fork per send plus the
  //     per-run token. Same fresh-instance send, registered restartable,
  //     chatter not built — compare with row 7.
  rows.add(
    BreakdownRow(
      'send · fresh instance, restartable, minLevel = warning',
      RowKind.real,
      await _withMinLevel(
        Level.warning,
        () => _sends(_RestartableBloc(), n, expectAll: false),
      ),
    ),
  );

  // 8. BURST shape, two sizes each: the hop depth alone, then the full
  //    send (fresh instance), the reused instance, and the full send with
  //    chatter not built.
  for (final size in [n ~/ 10, n]) {
    rows.add(
      BreakdownRow(
        '4 awaited async hops · burst n=$size',
        RowKind.synthetic,
        await _timeBurst(size, _hop4),
      ),
    );
    rows.add(
      BreakdownRow(
        'send · fresh instance · burst n=$size',
        RowKind.real,
        await _burst(_FreshBloc(), size),
      ),
    );
    rows.add(
      BreakdownRow(
        'send · reused instance · burst n=$size',
        RowKind.real,
        await _burst(_StatefulBloc(), size),
      ),
    );
    rows.add(
      BreakdownRow(
        'send · fresh, minLevel = warning · burst n=$size',
        RowKind.real,
        await _withMinLevel(Level.warning, () => _burst(_FreshBloc(), size)),
      ),
    );
  }

  return rows;
}

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
