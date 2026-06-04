import 'package:flutter/material.dart' show ThemeMode;

/// A persisted theme selection.
class ThemeSelection {
  final ThemeMode mode;
  final String? flavor;
  const ThemeSelection({required this.mode, this.flavor});
}

/// Vendor seam for persisting the theme selection.
///
/// `ThemeBloc` depends on this interface, not on a storage plugin, which makes
/// it testable without real storage: inject a fake. The default implementation
/// is `StorageThemePersistence` (backed by `StorageBloc`). Pass `null` for
/// in-memory-only (selection resets on restart).
abstract class ThemePersistence {
  /// Load the saved selection, or `null` if none.
  Future<ThemeSelection?> load();

  /// Persist the selection.
  Future<void> save(ThemeSelection selection);
}
