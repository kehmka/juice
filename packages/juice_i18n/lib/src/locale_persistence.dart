import 'package:flutter/widgets.dart' show Locale;

/// A persisted locale choice.
class LocaleChoice {
  final Locale locale;
  final bool followSystem;
  const LocaleChoice({required this.locale, required this.followSystem});
}

/// Vendor seam for remembering the chosen locale across restarts.
///
/// `I18nBloc` depends on this interface, not on storage — testable with a fake,
/// or `null` for no persistence. Default: `StorageLocalePersistence`.
abstract class LocalePersistence {
  /// Load the saved choice, or `null` if none.
  Future<LocaleChoice?> load();

  /// Persist the choice.
  Future<void> save(LocaleChoice choice);
}
