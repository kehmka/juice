import 'package:flutter/widgets.dart' show Locale;

import '../translation_source.dart';

/// In-memory [TranslationSource] from a `{ locale-code: { key: value } }` map.
///
/// Great for tests and small apps. Locale codes are matched by their
/// `toLanguageTag()` (e.g. `'en'`, `'en-US'`).
class MapTranslationSource implements TranslationSource {
  /// Keyed by locale tag, then translation key.
  final Map<String, Map<String, String>> translations;

  MapTranslationSource(this.translations);

  @override
  List<Locale> get supportedLocales =>
      translations.keys.map(_parseLocale).toList();

  @override
  Future<Map<String, String>> load(Locale locale) async {
    return translations[locale.toLanguageTag()] ??
        translations[locale.languageCode] ??
        const {};
  }

  @override
  Future<void> dispose() async {}

  static Locale _parseLocale(String tag) {
    final parts = tag.split(RegExp('[-_]'));
    return parts.length > 1 ? Locale(parts[0], parts[1]) : Locale(parts[0]);
  }
}
