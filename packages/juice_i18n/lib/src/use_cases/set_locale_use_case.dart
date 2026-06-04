import 'package:juice/juice.dart';

import '../i18n_bloc.dart';
import '../i18n_events.dart';
import 'i18n_load_mixin.dart';

/// Handles [SetLocaleEvent] — switch to an explicit locale.
class SetLocaleUseCase extends BlocUseCase<I18nBloc, SetLocaleEvent>
    with I18nLoad<SetLocaleEvent> {
  @override
  Future<void> execute(SetLocaleEvent event) async {
    await loadAndApply(event.locale, followSystem: false);
  }
}
