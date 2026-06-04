import 'dart:convert';

import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:flutter/widgets.dart' show Locale;

import '../translation_source.dart';

/// [TranslationSource] that loads flat JSON from bundled assets.
///
/// Expects one file per locale at `<basePath>/<localeTag>.json`, e.g.
/// `assets/i18n/en.json`, `assets/i18n/es.json`. The JSON is a flat
/// `{ "home.title": "Home", "cart.items.other": "{count} items" }` object.
///
/// Declare [supportedLocales] explicitly (assets can't be enumerated at
/// runtime) and list the files under `flutter: assets:` in your pubspec.
class AssetJsonTranslationSource implements TranslationSource {
  @override
  final List<Locale> supportedLocales;

  /// Asset directory holding `<localeTag>.json` files.
  final String basePath;

  /// Bundle to load from (overridable for tests).
  final AssetBundle bundle;

  AssetJsonTranslationSource({
    required this.supportedLocales,
    this.basePath = 'assets/i18n',
    AssetBundle? bundle,
  }) : bundle = bundle ?? rootBundle;

  @override
  Future<Map<String, String>> load(Locale locale) async {
    final raw = await bundle.loadString('$basePath/${locale.toLanguageTag()}.json');
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return decoded.map((k, v) => MapEntry(k, '$v'));
  }

  @override
  Future<void> dispose() async {}
}
