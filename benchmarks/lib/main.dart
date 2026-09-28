import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kProfileMode, kReleaseMode;
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:juice/juice.dart' show JuiceLoggerConfig;

import 'counters.dart';
import 'dispatch.dart';
import 'scenarios/all.dart';

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
    'os': Platform.operatingSystem,
    'cpus': Platform.numberOfProcessors,
  };

  final dispatch = await runDispatch();
  report['dispatch'] = [for (final r in dispatch) r.toJson()];

  // Frame benchmarks use the silent logger for every framework, so what is
  // compared is the widget-side cost (dispatch is reported separately).
  final defaultLogger = JuiceLoggerConfig.logger;
  JuiceLoggerConfig.configureLogger(SilentJuiceLogger());
  final frames = <Map<String, Object>>[];
  for (final variant in allVariants()) {
    frames.add(await _frameBench(host, variant));
  }
  JuiceLoggerConfig.configureLogger(defaultLogger);
  report['frames'] = frames;

  stdout.writeln('BENCH_JSON_BEGIN');
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(report));
  stdout.writeln('BENCH_JSON_END');
  await stdout.flush();
  exit(0);
}

Future<void> _frame() {
  SchedulerBinding.instance.scheduleFrame();
  return SchedulerBinding.instance.endOfFrame;
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
