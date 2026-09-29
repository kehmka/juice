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
/// - `4 async hops`        — four nested awaited async calls, the depth of
///                           send → dispatcher → executor → execute().
///
/// BURST shape (2026-09-29): the dispatch benchmark found Juice's burst
/// (fire all, await the last) SLOWER per event than its sequential shape,
/// on every machine, while bloc and Riverpod get cheaper in burst. These
/// rows fire the same ops without awaiting each one, at two sizes: a cost
/// that grows with the size is depth (microtask queue, allocation/GC), a
/// flat one is per event.
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

class _StatefulBloc extends JuiceBloc<_S> {
  _StatefulBloc()
    : super(const _S(0), [
        () => StatefulUseCaseBuilder(
          typeOfEvent: _Ev,
          useCaseGenerator: () => _StatefulUC(),
        ),
      ]);
}

class BreakdownRow {
  BreakdownRow(this.layer, this.kind, this.micros);
  final String layer;
  final String kind; // 'real' | 'synthetic'
  final double micros;
}

/// A layer's rounds gathered: median, range, spread.
class BreakdownResult {
  BreakdownResult(this.layer, this.kind, this.sample);
  final String layer;
  final String kind;
  final Sample sample;
  Map<String, Object> toJson() => {
    'layer': layer,
    'kind': kind,
    ...sample.toJson('microsPerOp'),
  };
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

/// Written by the synthetic map benchmark so the maps can't be optimized
/// away; read by [runBreakdown]'s result.
Object? sink;

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
      'real',
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
      'real',
      _timeSync(n, (i) {
        emitter.emitUpdate(_Ev(), _S(i), {'g'});
      }),
    ),
  );
  await Future<void>.delayed(Duration.zero);
  await sub.cancel();
  await sm.close();

  // 3. Telemetry maps alone (synthetic).
  final uc = _UC();
  final ev = _Ev();
  rows.add(
    BreakdownRow(
      'telemetry maps (3 per event)',
      'synthetic',
      _timeSync(n, (i) {
        final useCaseName = uc.runtimeType.toString();
        final eventName = ev.runtimeType.toString();
        sink = {
          'type': 'use_case_execution',
          'useCase': useCaseName,
          'event': eventName,
          'executionId': i,
        };
        sink = {
          'type': 'state_emission',
          'status': 'update',
          'state': i,
          'bloc': '_FreshBloc',
          'groups': const {'g'},
          'event': eventName,
        };
        sink = {
          'type': 'use_case_completed',
          'useCase': useCaseName,
          'event': eventName,
          'executionId': i,
          'elapsedMicros': i,
        };
      }),
    ),
  );

  // 4. Async hop depth alone (synthetic).
  rows.add(
    BreakdownRow(
      '4 awaited async hops',
      'synthetic',
      await _timeAsync(n, _hop4),
    ),
  );

  // 5. Full send, one reused use-case instance.
  final stateful = _StatefulBloc();
  rows.add(
    BreakdownRow(
      'send · StatefulUseCaseBuilder (reused instance)',
      'real',
      await _timeAsync(n, (_) => stateful.send(_Ev())),
    ),
  );
  await stateful.close();

  // 6. Full send, fresh instance per event (the normal registration).
  final fresh = _FreshBloc();
  rows.add(
    BreakdownRow(
      'send · UseCaseBuilder (fresh instance)',
      'real',
      await _timeAsync(n, (_) => fresh.send(_Ev())),
    ),
  );
  await fresh.close();

  // 7. The same send with the framework's chatter NOT BUILT
  //    (JuiceLoggerConfig.minLevel = Level.warning, juice ≥ 1.10.0) — the
  //    one knob the breakdown priced.
  final savedLevel = JuiceLoggerConfig.minLevel;
  JuiceLoggerConfig.minLevel = Level.warning;
  final quiet = _FreshBloc();
  rows.add(
    BreakdownRow(
      'send · fresh instance, minLevel = warning (chatter not built)',
      'real',
      await _timeAsync(n, (_) => quiet.send(_Ev())),
    ),
  );
  await quiet.close();
  JuiceLoggerConfig.minLevel = savedLevel;

  // 7b. The same send with NOTHING configured but the default logger
  //     (juice ≥ 1.10.0): DefaultJuiceLogger declares what its filter
  //     keeps — nothing outside debug — so in a release build this row
  //     should land on row 7 with no knob set.
  final configured = JuiceLoggerConfig.logger;
  JuiceLoggerConfig.configureLogger(DefaultJuiceLogger());
  final unconfigured = _FreshBloc();
  rows.add(
    BreakdownRow(
      'send · fresh instance, DefaultJuiceLogger, no knob set',
      'real',
      await _timeAsync(n, (_) => unconfigured.send(_Ev())),
    ),
  );
  await unconfigured.close();
  JuiceLoggerConfig.configureLogger(configured);

  // 8. BURST shape, two sizes each: the hop depth alone, then the full
  //    send (fresh instance) and the full send with chatter not built.
  for (final size in [n ~/ 10, n]) {
    rows.add(
      BreakdownRow(
        '4 awaited async hops · burst n=$size',
        'synthetic',
        await _timeBurst(size, _hop4),
      ),
    );
    final b = _FreshBloc();
    rows.add(
      BreakdownRow(
        'send · fresh instance · burst n=$size',
        'real',
        await _timeBurst(size, (_) => b.send(_Ev())),
      ),
    );
    await b.close();
    final s = _StatefulBloc();
    rows.add(
      BreakdownRow(
        'send · reused instance · burst n=$size',
        'real',
        await _timeBurst(size, (_) => s.send(_Ev())),
      ),
    );
    await s.close();
    JuiceLoggerConfig.minLevel = Level.warning;
    final q = _FreshBloc();
    rows.add(
      BreakdownRow(
        'send · fresh, minLevel = warning · burst n=$size',
        'real',
        await _timeBurst(size, (_) => q.send(_Ev())),
      ),
    );
    await q.close();
    JuiceLoggerConfig.minLevel = savedLevel;
  }

  return rows;
}

/// Warm-up, then EVERY round per layer (median + range in the report).
Future<List<BreakdownResult>> runBreakdown({
  int n = 20000,
  int rounds = 5,
}) async {
  final previous = JuiceLoggerConfig.logger;
  JuiceLoggerConfig.configureLogger(SilentJuiceLogger());
  await _once(n);
  final all = <String, (String, List<double>)>{};
  for (var r = 0; r < rounds; r++) {
    for (final row in await _once(n)) {
      all.putIfAbsent(row.layer, () => (row.kind, [])).$2.add(row.micros);
    }
  }
  JuiceLoggerConfig.configureLogger(previous);
  return [
    for (final e in all.entries)
      BreakdownResult(e.key, e.value.$1, Sample(e.value.$2)),
  ];
}
