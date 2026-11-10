import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_observability_devtools_extension/src/telemetry_model.dart';
import 'package:juice_observability_devtools_extension/src/tone_color.dart';

/// The colour a timeline row's type is drawn in, per tone, on each
/// brightness. The rule this pins: ONLY a problem is drawn in the error
/// colour.
void main() {
  Future<Map<JuiceEventTone, Color?>> colorsUnder(
    WidgetTester tester,
    ThemeData theme,
  ) async {
    late Map<JuiceEventTone, Color?> colors;
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Builder(
          builder: (context) {
            colors = {
              for (final tone in JuiceEventTone.values)
                tone: toneColor(context, tone),
            };
            return const SizedBox();
          },
        ),
      ),
    );
    return colors;
  }

  for (final brightness in Brightness.values) {
    final theme = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.indigo,
        brightness: brightness,
      ),
    );
    final scheme = theme.colorScheme;

    testWidgets('${brightness.name}: only a problem is the error colour', (
      tester,
    ) async {
      final colors = await colorsUnder(tester, theme);
      expect(colors[JuiceEventTone.problem], scheme.error);
      for (final tone in JuiceEventTone.values) {
        if (tone == JuiceEventTone.problem) continue;
        expect(colors[tone], isNot(scheme.error), reason: tone.name);
      }
    });

    testWidgets('${brightness.name}: each tone has its colour', (tester) async {
      final colors = await colorsUnder(tester, theme);
      expect(colors[JuiceEventTone.started], scheme.primary);
      expect(colors[JuiceEventTone.completed], scheme.tertiary);
      expect(colors[JuiceEventTone.emission], scheme.secondary);
      expect(colors[JuiceEventTone.quiet], scheme.outline);
      expect(
        colors[JuiceEventTone.plain],
        isNull,
        reason: 'plain keeps the row\'s own text colour',
      );
      expect(
        colors[JuiceEventTone.warning],
        brightness == Brightness.dark
            ? Colors.amber.shade300
            : Colors.orange.shade900,
      );
    });
  }
}
