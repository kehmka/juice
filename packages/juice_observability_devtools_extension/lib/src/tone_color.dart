import 'package:flutter/material.dart';

import 'telemetry_model.dart';

/// The text colour of a timeline row's type, by its [JuiceEventTone]; null
/// for [JuiceEventTone.plain], which keeps the row's own text colour.
///
/// Here rather than in `views.dart` so it can be tested on the VM: the
/// views import the live store, which is web-only.
Color? toneColor(BuildContext context, JuiceEventTone tone) {
  final theme = Theme.of(context);
  final s = theme.colorScheme;
  return switch (tone) {
    JuiceEventTone.problem => s.error,
    // Material's scheme has no warning role: an amber that holds its
    // contrast on each brightness.
    JuiceEventTone.warning =>
      theme.brightness == Brightness.dark
          ? Colors.amber.shade300
          : Colors.orange.shade900,
    JuiceEventTone.started => s.primary,
    JuiceEventTone.completed => s.tertiary,
    JuiceEventTone.emission => s.secondary,
    JuiceEventTone.quiet => s.outline,
    JuiceEventTone.plain => null,
  };
}
