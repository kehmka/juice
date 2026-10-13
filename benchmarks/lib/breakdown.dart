// ignore_for_file: implementation_imports, invalid_use_of_internal_member
import 'package:juice/juice.dart';
import 'package:juice/src/bloc/src/core/state_manager.dart';
import 'package:juice/src/bloc/src/core/status_emitter.dart';

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

/// Times [n] sends on a fresh [bloc], then closes it.
Future<double> _sends(JuiceBloc<_S> bloc, int n) async {
  final micros = await _timeAsync(n, (_) => bloc.send(_Ev()));
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
      await _withMinLevel(Level.warning, () => _sends(_RestartableBloc(), n)),
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
