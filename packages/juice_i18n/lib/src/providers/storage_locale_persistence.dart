import 'package:flutter/widgets.dart' show Locale;
import 'package:juice_storage/juice_storage.dart';

import '../locale_persistence.dart';

/// Default [LocalePersistence] backed by `StorageBloc` (SharedPreferences).
///
/// Deliberately logic-light: stores the locale tag and follow-system flag as
/// prefs values. All behavior lives in `I18nBloc`, tested with a fake.
class StorageLocalePersistence implements LocalePersistence {
  final StorageBloc storageBloc;
  final String prefix;

  StorageLocalePersistence(this.storageBloc, {this.prefix = 'juice_i18n'});

  String get _localeKey => '${prefix}_locale';
  String get _followKey => '${prefix}_follow_system';

  @override
  Future<LocaleChoice?> load() async {
    final tag = await storageBloc.prefsRead<String>(_localeKey);
    if (tag == null) return null;
    final follow = await storageBloc.prefsRead<bool>(_followKey) ?? false;
    return LocaleChoice(locale: _parse(tag), followSystem: follow);
  }

  @override
  Future<void> save(LocaleChoice choice) async {
    await storageBloc.prefsWrite(_localeKey, choice.locale.toLanguageTag());
    await storageBloc.prefsWrite(_followKey, choice.followSystem);
  }

  static Locale _parse(String tag) {
    final parts = tag.split(RegExp('[-_]'));
    return parts.length > 1 ? Locale(parts[0], parts[1]) : Locale(parts[0]);
  }
}
