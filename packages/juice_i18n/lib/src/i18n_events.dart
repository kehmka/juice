import 'package:juice/juice.dart';

import 'i18n_config.dart';

/// Base class for i18n events.
abstract class I18nEvent extends EventBase {
  @override
  String toString() => runtimeType.toString();
}

/// Configure the source/persistence and load the initial locale.
class InitializeI18nEvent extends I18nEvent {
  final I18nConfig config;
  InitializeI18nEvent({required this.config});
}

/// Switch to an explicit locale.
class SetLocaleEvent extends I18nEvent {
  final Locale locale;
  SetLocaleEvent(this.locale);
}

/// Follow the platform locale.
class UseSystemLocaleEvent extends I18nEvent {}
