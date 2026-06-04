import 'package:juice/juice.dart';

import '../theme_bloc.dart';
import '../theme_events.dart';
import '../theme_state.dart';
import 'theme_emit_mixin.dart';

/// Handles [SetThemeModeEvent].
class SetThemeModeUseCase extends BlocUseCase<ThemeBloc, SetThemeModeEvent>
    with ThemeEmit<SetThemeModeEvent> {
  @override
  Future<void> execute(SetThemeModeEvent event) async {
    if (event.mode == bloc.state.mode) return;
    await commit(bloc.state.copyWith(mode: event.mode), {ThemeGroups.mode});
  }
}
