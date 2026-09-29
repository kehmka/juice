import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kProfileMode, kReleaseMode;
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:juice/juice.dart' show JuiceLoggerConfig;

import 'counters.dart';
import 'dispatch.dart';
import 'scenarios/all.dart';
import 'stats.dart';

/// The timing half of the benchmarks. Built in RELEASE (AOT) and run headless
/// by tool/run.sh; prints one JSON document between markers, then exits.
///
/// Two measurements:
/// 1. dispatch cost (lib/dispatch.dart) — no widgets;
/// 2. rebuild frame cost — each variant mounts [frameCells] cells, then
///    [frameUpdates] times updates ONE cell and waits for the frame; we
///    record the engine's FrameTiming.buildDuration (UI thread: build +
///    layout + paint) for those frames. Raster time is excluded on purpose:
///    under a virtual display it measures a software rasterizer.
const frameCells = 1000;
const frameUpdates = 300;
const frameRounds = 3;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final host = ValueNotifier<Widget>(const SizedBox());
  runApp(
    Directionality(
      textDirection: TextDirection.ltr,
      child: ValueListenableBuilder<Widget>(
        valueListenable: host,
        builder: (_, w, __) => w,
      ),
    ),
  );
  _run(host);
}

Future<void> _run(ValueNotifier<Widget> host) async {
  final report = <String, Object>{
    'mode': kReleaseMode ? 'release' : (kProfileMode ? 'profile' : 'debug'),
    'dart': Platform.version.split(' ').first,
    // Injected by tool/run.sh (--dart-define); TOOLCHAIN pins it.
    'flutter': const String.fromEnvironment(
      'BENCH_FLUTTER',
      defaultValue: 'unknown',
    ),
    'toolchainDrift': const bool.fromEnvironment('BENCH_TOOLCHAIN_DRIFT'),
    'os': Platform.operatingSystem,
    'cpus': Platform.numberOfProcessors,
  };

  progress('start');
  final dispatch = await runDispatch();
  report['dispatch'] = [for (final r in dispatch) r.toJson()];
  report['dispatchComparisons'] = {
    for (final shape in ['sequential', 'burst'])
      shape: compare({
        for (final r in dispatch)
          if (r.shape == shape) r.name: r.sample,
      }),
  };
  progress('dispatch done');

  // Frame benchmarks use the silent logger for every framework, so what is
  // compared is the widget-side cost (dispatch is reported separately).
  final defaultLogger = JuiceLoggerConfig.logger;
  JuiceLoggerConfig.configureLogger(SilentJuiceLogger());
  // Each variant runs frameRounds times; the p50 of each round is a sample,
  // so a variant's frame cost carries a range like everything else.
  final frameSamples = <String, (Variant, List<Map<String, Object>>)>{};
  for (var round = 0; round < frameRounds; round++) {
    for (final variant in allVariants()) {
      progress('frames r$round: ${variant.name} …');
      final r = await _frameBench(host, variant);
      frameSamples.putIfAbsent(variant.name, () => (variant, [])).$2.add(r);
      progress('frames r$round: ${variant.name} done');
    }
  }
  JuiceLoggerConfig.configureLogger(defaultLogger);
  final frames = <Map<String, Object>>[];
  final tunedP50 = <String, Sample>{};
  for (final e in frameSamples.entries) {
    final runs = e.value.$2;
    final p50 = Sample([
      for (final r in runs) (r['buildMicrosP50'] as int).toDouble(),
    ]);
    final p90 = Sample([
      for (final r in runs) (r['buildMicrosP90'] as int).toDouble(),
    ]);
    final builds = runs.first['buildsPerUpdate'] as double;
    frames.add({
      'variant': e.key,
      'framework': e.value.$1.framework,
      'cells': frameCells,
      'updates': frameUpdates,
      'rounds': runs.length,
      'buildsPerUpdate': builds,
      'buildMicrosP50': p50.toJson('median'),
      'buildMicrosP90': p90.toJson('median'),
    });
    if (builds < 2) tunedP50[e.key] = p50;
  }
  report['frames'] = frames;
  report['frameComparisons'] = {'tunedP50': compare(tunedP50)};

  emit('BENCH_JSON_BEGIN');
  emit(const JsonEncoder.withIndent('  ').convert(report));
  emit('BENCH_JSON_END');
  await stdout.flush();
  exit(0);
}

/// One frame. The engine only delivers frames to a VISIBLE window — an
/// occluded macOS window or a backgrounded phone app gets none, and this
/// await would sit forever at 0% CPU. So a frame that takes more than
/// [stallAfter] is reported (once) as BENCH_STALLED, with the reason; the
/// await itself still completes as soon as the window is visible again.
const stallAfter = Duration(seconds: 5);
bool _stallReported = false;
Future<void> _frame() async {
  SchedulerBinding.instance.scheduleFrame();
  final done = SchedulerBinding.instance.endOfFrame;
  await Future.any([
    done,
    Future<void>.delayed(stallAfter).then((_) {
      if (!_stallReported) {
        _stallReported = true;
        emit(
          'BENCH_STALLED no frame for ${stallAfter.inSeconds}s — the '
          'window is occluded or the app is backgrounded; bring it to the '
          'front (frames resume, timing of THIS variant is suspect)',
        );
      }
    }),
  ]);
  await done;
}

Future<Map<String, Object>> _frameBench(
  ValueNotifier<Widget> host,
  Variant variant,
) async {
  variant.setUp(frameCells);
  Counters.reset(frameCells);
  host.value = variant.build(frameCells);
  await _frame();
  await _frame();

  final timings = <FrameTiming>[];
  void collect(List<FrameTiming> t) => timings.addAll(t);
  SchedulerBinding.instance.addTimingsCallback(collect);

  Counters.reset(frameCells);
  for (var k = 1; k <= frameUpdates; k++) {
    await variant.update(k % frameCells, k);
    await _frame();
  }
  // FrameTimings are delivered in batches; give the engine time to flush.
  await Future<void>.delayed(const Duration(seconds: 2));
  await _frame();
  SchedulerBinding.instance.removeTimingsCallback(collect);

  final builds = Counters.totalBuilds;
  host.value = const SizedBox();
  await _frame();
  await variant.tearDown();

  final micros =
      timings
          .map((t) => t.buildDuration.inMicroseconds)
          .where((us) => us > 0)
          .toList()
        ..sort();
  int pct(double p) =>
      micros.isEmpty ? 0 : micros[((micros.length - 1) * p).round()];
  return {
    'variant': variant.name,
    'framework': variant.framework,
    'cells': frameCells,
    'updates': frameUpdates,
    'framesTimed': micros.length,
    'buildsPerUpdate': builds / frameUpdates,
    'buildMicrosP50': pct(0.5),
    'buildMicrosP90': pct(0.9),
  };
}

/// The JSON goes to stdout on every platform: tool/run.sh reads it on
/// desktop, and `devicectl device process launch --console` over a CABLE
/// captures it on a phone (a wireless tunnel drops; `print` on iOS goes to
/// os_log, not stdout). On a phone it is ALSO written to the app's
/// Documents dir as a backup, and a failed write is loud, never silent.
void emit(String line) {
  stdout.writeln(line);
  if (Platform.isIOS || Platform.isAndroid) _persist(line);
}

final _buf = StringBuffer();
void _persist(String line) {
  if (line == 'BENCH_JSON_BEGIN') {
    _buf.clear();
    return;
  }
  if (line != 'BENCH_JSON_END') {
    _buf.writeln(line);
    return;
  }
  // Documents sits beside tmp in the sandbox; systemTemp is always set.
  final path =
      '${Directory.systemTemp.parent.path}/Documents/bench_timing.json';
  try {
    File(path).writeAsStringSync(_buf.toString());
    stdout.writeln('BENCH_WROTE $path');
  } catch (e) {
    stdout.writeln('BENCH_WRITE_FAILED $path: $e');
    rethrow;
  }
}

/// Phase markers on stdout (captured by the console) so a stuck run can be
/// located.
void progress(String what) => stdout.writeln('BENCH_PROGRESS $what');
