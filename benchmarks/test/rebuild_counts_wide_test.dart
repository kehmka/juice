import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';
import 'package:juice_benchmarks/counters.dart';
import 'package:juice_benchmarks/scenarios/wide.dart';
import 'dart:convert';
import 'dart:io';

/// REBUILD COUNTS, WIDE SCENARIO — deterministic. 100 cells + a header; each
/// update sets K = 5 consecutive cells. Fixed in advance (lib/scenarios/wide.dart):
/// tuned forms build K + 1 widgets per update, naive forms N + 1.
const cells = 100;
const updates = 10;

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
  final k = wideK(cells);

  for (final variant in wideVariants()) {
    testWidgets(variant.name, (tester) async {
      variant.setUp(cells);
      Counters.reset(cells);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: variant.build(cells),
        ),
      );
      Counters.reset(cells);
      for (var u = 1; u <= updates; u++) {
        final done = variant.update((u * 7) % cells, u);
        await tester.pump();
        await tester.pump();
        await done;
      }
      final cellBuilds = Counters.totalBuilds / updates;
      final headerBuilds = Counters.headerBuilds / updates;
      final selectors = Counters.selectorCalls / updates;
      results.add({
        'variant': variant.name,
        'framework': variant.framework,
        'mechanism': variant.mechanism,
        'k': k,
        'cellBuildsPerUpdate': cellBuilds,
        'headerBuildsPerUpdate': headerBuilds,
        'buildsPerUpdate': cellBuilds + headerBuilds,
        'selectorCallsPerUpdate': selectors,
      });
      final targeted = !variant.mechanism.contains('the default');
      expect(
        cellBuilds,
        targeted ? k : cells,
        reason: '${variant.name} cell builds',
      );
      expect(headerBuilds, 1, reason: '${variant.name} header builds');
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      variant.tearDown().ignore();
      await tester.pump(const Duration(milliseconds: 50));
    });
  }

  tearDownAll(() {
    File('results/rebuild_counts_wide.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'cells': cells,
        'k': k,
        'updates': updates,
        'results': results,
      }),
    );
  });
}
