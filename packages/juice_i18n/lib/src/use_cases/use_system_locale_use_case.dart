import 'package:juice/juice.dart';

import '../i18n_bloc.dart';
import '../i18n_events.dart';
import 'i18n_load_mixin.dart';

/// Handles [UseSystemLocaleEvent] — follow the platform locale.
class UseSystemLocaleUseCase extends BlocUseCase<I18nBloc, UseSystemLocaleEvent>
    with I18nLoad<UseSystemLocaleEvent> {
  @override
  Future<void> execute(UseSystemLocaleEvent event) async {
    await loadAndApply(bloc.systemLocale(), followSystem: true);
  }
}
