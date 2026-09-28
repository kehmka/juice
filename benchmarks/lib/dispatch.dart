import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:juice/juice.dart';

import 'scenarios/cells_bloc.dart' as b;
import 'scenarios/cells_juice.dart' as j;
import 'scenarios/cells_riverpod.dart' as r;

/// DISPATCH COST — the framework's own overhead to turn "change cell i" into
/// a new state observable by a listener, with no widgets involved.
///
/// Two shapes per framework:
/// - `sequential`: await each update before the next (per-update latency);
/// - `burst`: fire all updates, then await the last (throughput).
///
/// The frameworks do different amounts of work per update, and that is the
/// point being measured: Juice dispatches an event to a use case with
/// telemetry spans; bloc routes an event through an event stream to a
/// handler; Riverpod calls a notifier method synchronously (no event queue).
class DispatchResult {
  DispatchResult(this.name, this.shape, this.updates, this.elapsed);
  final String name;
  final String shape;
  final int updates;
  final Duration elapsed;

  double get microsPerUpdate => elapsed.inMicroseconds / updates;

  Map<String, Object> toJson() => {
    'variant': name,
    'shape': shape,
    'updates': updates,
    'microsPerUpdate': double.parse(microsPerUpdate.toStringAsFixed(3)),
  };
}

/// A logger that drops everything — isolates Juice's framework cost from the
/// cost of its default telemetry formatting.
class SilentJuiceLogger implements JuiceLogger {
  @override
  void log(
    String message, {
    Level level = Level.info,
    Map<String, dynamic>? context,
  }) {}

  @override
  void logError(
    String message,
    Object error,
    StackTrace stackTrace, {
    Map<String, dynamic>? context,
  }) {}
}

typedef _Setup = Future<_Target> Function();

class _Target {
  _Target(this.update, this.close);
  final Future<void> Function(int i, int v) update;

  /// Fires without awaiting; returns the future of the LAST processed update.
  final Future<void> Function() close;
}

const _cells = 100;

Future<_Target> _juice() async {
  final bloc = j.CellsBloc(_cells);
  return _Target(
    (i, v) => bloc.send(j.SetCellEvent(i, v, grouped: true)),
    bloc.close,
  );
}

Future<_Target> _bloc() async {
  final bloc = b.CellsBloc(_cells);
  return _Target((i, v) {
    final next = bloc.stream.first;
    bloc.add(b.SetCell(i, v));
    return next;
  }, bloc.close);
}

Future<_Target> _riverpod() async {
  final provider = NotifierProvider<r.CellsNotifier, List<int>>(
    () => r.CellsNotifier(_cells),
  );
  final container = ProviderContainer();
  // A listener, so a state change has an observer to notify (as the other
  // two have their stream).
  final sub = container.listen(provider, (_, __) {});
  final notifier = container.read(provider.notifier);
  return _Target((i, v) async => notifier.set(i, v), () async {
    sub.close();
    container.dispose();
  });
}

Future<DispatchResult> _sequential(String name, _Setup setup, int n) async {
  final t = await setup();
  final sw = Stopwatch()..start();
  for (var k = 0; k < n; k++) {
    await t.update(k % _cells, k);
  }
  sw.stop();
  await t.close();
  return DispatchResult(name, 'sequential', n, sw.elapsed);
}

Future<DispatchResult> _burst(String name, _Setup setup, int n) async {
  final t = await setup();
  final sw = Stopwatch()..start();
  Future<void>? last;
  for (var k = 0; k < n; k++) {
    last = t.update(k % _cells, k);
  }
  await last;
  sw.stop();
  await t.close();
  return DispatchResult(name, 'burst', n, sw.elapsed);
}

/// Bloc's burst: `stream.first` per update would resolve on the FIRST
/// state, not each one; wait for the Nth emission instead.
Future<DispatchResult> _blocBurst(int n) async {
  final bloc = b.CellsBloc(_cells);
  final done = bloc.stream.take(n).last;
  final sw = Stopwatch()..start();
  for (var k = 0; k < n; k++) {
    bloc.add(b.SetCell(k % _cells, k));
  }
  await done;
  sw.stop();
  await bloc.close();
  return DispatchResult('bloc', 'burst', n, sw.elapsed);
}

/// Runs every dispatch benchmark [rounds] times after a warm-up and keeps
/// the fastest round per (variant, shape) — the least-disturbed run.
Future<List<DispatchResult>> runDispatch({
  int n = 20000,
  int rounds = 5,
}) async {
  final defaultLogger = JuiceLoggerConfig.logger;

  Future<List<DispatchResult>> once() async {
    final out = <DispatchResult>[];
    JuiceLoggerConfig.configureLogger(defaultLogger);
    out.add(await _sequential('juice (default logger)', _juice, n));
    out.add(await _burst('juice (default logger)', _juice, n));
    JuiceLoggerConfig.configureLogger(SilentJuiceLogger());
    out.add(await _sequential('juice (silent logger)', _juice, n));
    out.add(await _burst('juice (silent logger)', _juice, n));
    out.add(await _sequential('bloc', _bloc, n));
    out.add(await _blocBurst(n));
    out.add(await _sequential('riverpod', _riverpod, n));
    out.add(await _burst('riverpod', _riverpod, n));
    return out;
  }

  await once(); // warm-up (JIT/AOT caches, allocator)
  final best = <String, DispatchResult>{};
  for (var i = 0; i < rounds; i++) {
    for (final r in await once()) {
      final key = '${r.name}/${r.shape}';
      final prev = best[key];
      if (prev == null || r.elapsed < prev.elapsed) best[key] = r;
    }
  }
  JuiceLoggerConfig.configureLogger(defaultLogger);
  return best.values.toList();
}
