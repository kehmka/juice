import 'package:flutter/material.dart' show ThemeMode;
import 'package:juice_storage/juice_storage.dart';

import '../theme_persistence.dart';

/// Default [ThemePersistence] backed by `StorageBloc` (SharedPreferences).
///
/// Deliberately logic-light: stores `mode` and `flavor` as prefs strings. All
/// behavior lives in `ThemeBloc`, tested with a fake persistence.
class StorageThemePersistence implements ThemePersistence {
  final StorageBloc storageBloc;
  final String prefix;

  StorageThemePersistence(this.storageBloc, {this.prefix = 'juice_theme'});

  String get _modeKey => '${prefix}_mode';
  String get _flavorKey => '${prefix}_flavor';

  @override
  Future<ThemeSelection?> load() async {
    final modeName = await storageBloc.prefsRead<String>(_modeKey);
    if (modeName == null) return null;
    final mode = ThemeMode.values.firstWhere(
      (m) => m.name == modeName,
      orElse: () => ThemeMode.system,
    );
    final flavor = await storageBloc.prefsRead<String>(_flavorKey);
    return ThemeSelection(mode: mode, flavor: flavor);
  }

  @override
  Future<void> save(ThemeSelection selection) async {
    await storageBloc.prefsWrite(_modeKey, selection.mode.name);
    final flavor = selection.flavor;
    if (flavor != null) {
      await storageBloc.prefsWrite(_flavorKey, flavor);
    } else {
      await storageBloc.prefsDelete(_flavorKey);
    }
  }
}
