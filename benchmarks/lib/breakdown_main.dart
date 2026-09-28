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
  stdout.writeln('BENCH_JSON_BEGIN');
  stdout.writeln(
    const JsonEncoder.withIndent('  ').convert({
      'dart': Platform.version.split(' ').first,
      'cpus': Platform.numberOfProcessors,
      'breakdown': [for (final r in rows) r.toJson()],
    }),
  );
  stdout.writeln('BENCH_JSON_END');
  await stdout.flush();
  exit(0);
}
