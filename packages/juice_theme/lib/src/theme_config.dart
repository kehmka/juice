import 'package:flutter/material.dart' show ThemeMode;

import 'theme_persistence.dart';

/// Configuration for [ThemeBloc].
class ThemeConfig {
  /// Where the selection is persisted. `null` = in-memory only (resets on
  /// restart). Default impl: `StorageThemePersistence`.
  final ThemePersistence? persistence;

  /// Mode to use when nothing is persisted yet.
  final ThemeMode defaultMode;

  /// Flavor to use when nothing is persisted yet.
  final String? defaultFlavor;

  const ThemeConfig({
    this.persistence,
    this.defaultMode = ThemeMode.system,
    this.defaultFlavor,
  });
}
