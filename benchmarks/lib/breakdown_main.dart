import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';

import 'breakdown.dart';

/// Entry point for the dispatch breakdown (lib/breakdown.dart):
///   flutter build linux --release -t lib/breakdown_main.dart
/// Prints one JSON document between markers, then exits.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final rows = await runBreakdown();
  emit('BENCH_JSON_BEGIN');
  emit(
    const JsonEncoder.withIndent('  ').convert({
      'dart': Platform.version.split(' ').first,
      'cpus': Platform.numberOfProcessors,
      'breakdown': [for (final r in rows) r.toJson()],
    }),
  );
  emit('BENCH_JSON_END');
  await stdout.flush();
  exit(0);
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
      '${Directory.systemTemp.parent.path}/Documents/bench_breakdown.json';
  try {
    File(path).writeAsStringSync(_buf.toString());
    stdout.writeln('BENCH_WROTE $path');
  } catch (e) {
    stdout.writeln('BENCH_WRITE_FAILED $path: $e');
    rethrow;
  }
}
