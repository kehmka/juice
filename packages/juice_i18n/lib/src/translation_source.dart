import 'package:flutter/widgets.dart' show Locale;

/// Vendor seam for *where translation strings come from*.
///
/// `I18nBloc` depends on this interface, so it's testable with an in-memory
/// source and pluggable to assets, a backend, or a gen-l10n wrapper. Defaults:
/// `MapTranslationSource`, `AssetJsonTranslationSource`.
///
/// Keys are flat strings (e.g. `'home.title'`); pluralization uses sub-keys
/// (`'cart.items.one'` / `'cart.items.other'`).
abstract class TranslationSource {
  /// Locales this source can serve.
  List<Locale> get supportedLocales;

  /// Load the flat key→string map for [locale].
  Future<Map<String, String>> load(Locale locale);

  /// Release any resources.
  Future<void> dispose();
}
