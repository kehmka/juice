import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart' show JuiceLoggerConfig, JuiceLogger, Level;
import 'package:juice_benchmarks/counters.dart';
import 'package:juice_benchmarks/scenarios/all.dart';

/// REBUILD COUNTS — deterministic, so they are both a published result and a
/// regression pin. 100 cell widgets; cell 7 is updated 10 times; we count how
/// many cell widgets BUILT per update and how many consumer-side selector
/// calls ran per update. Build mode doesn't change these numbers.

const cells = 100;
const updates = 10;
const target = 7;

class _Silent implements JuiceLogger {
  @override
  void log(
    String m, {
    Level level = Level.info,
    Map<String, dynamic>? context,
  }) {}
  @override
  void logError(
    String m,
    Object e,
    StackTrace s, {
    Map<String, dynamic>? context,
  }) {}
}

void main() {
  setUpAll(() => JuiceLoggerConfig.configureLogger(_Silent()));
  final results = <Map<String, Object?>>[];

  for (final variant in allVariants()) {
    testWidgets(variant.name, (tester) async {
      variant.setUp(cells);
      Counters.reset(cells); // size the counters before the first build
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: variant.build(cells),
        ),
      );
      Counters.reset(cells);

      for (var k = 1; k <= updates; k++) {
        // Everything runs in the test's fake-async zone (where the blocs
        // were created): start the update, pump to flush its microtasks and
        // render the frame, then the update's future has completed.
        final done = variant.update(target, k);
        await tester.pump();
        await tester.pump();
        await done;
      }
      expect(
        find.text('$updates'),
        findsOneWidget,
        reason: 'the target cell shows the last value',
      );

      final buildsPerUpdate = Counters.totalBuilds / updates;
      final selectorsPerUpdate = Counters.selectorCalls / updates;
      final othersBuilt = [
        for (var i = 0; i < cells; i++)
          if (i != target && Counters.builds[i] > 0) i,
      ].length;
      results.add({
        'variant': variant.name,
        'framework': variant.framework,
        'mechanism': variant.mechanism,
        'buildsPerUpdate': buildsPerUpdate,
        'selectorCallsPerUpdate': selectorsPerUpdate,
        'untouchedCellsRebuilt': othersBuilt,
      });

      // Pins: a targeted variant rebuilds exactly the changed cell; a
      // broadcast variant rebuilds all of them.
      final targeted = !variant.mechanism.contains('the default');
      expect(
        buildsPerUpdate,
        targeted ? 1 : cells,
        reason: '${variant.name} builds per update',
      );

      // Teardown is not measured. Pump fake time while it runs, but don't
      // await it: flutter_bloc's Bloc.close() never completes under the
      // widget tester's fake-async zone (it waits on work outside it). Juice
      // and Riverpod finish within the first pumps.
      await tester.pumpWidget(const SizedBox());
      var closed = false;
      unawaited(variant.tearDown().then((_) => closed = true));
      for (var i = 0; i < 50 && !closed; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
    });
  }

  tearDownAll(() {
    File('results/rebuild_counts.json').writeAsStringSync(
      const JsonEncoder.withIndent(
        '  ',
      ).convert({'cells': cells, 'updates': updates, 'results': results}),
    );
    // ignore: avoid_print
    print(_table(results));
  });
}

String _table(List<Map<String, Object?>> rows) {
  final b = StringBuffer()
    ..writeln(
      '| variant | builds / update | selector calls / update | '
      'mechanism |',
    )
    ..writeln('|---|---:|---:|---|');
  for (final r in rows) {
    b.writeln(
      '| ${r['variant']} | ${r['buildsPerUpdate']} | '
      '${r['selectorCallsPerUpdate']} | ${r['mechanism']} |',
    );
  }
  return b.toString();
}
