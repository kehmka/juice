import 'package:juice/juice.dart';

import '../theme_bloc.dart';
import '../theme_events.dart';
import '../theme_state.dart';
import 'theme_emit_mixin.dart';

/// Handles [ToggleThemeEvent] — flip light⇄dark (system → dark).
class ToggleThemeUseCase extends BlocUseCase<ThemeBloc, ToggleThemeEvent>
    with ThemeEmit<ToggleThemeEvent> {
  @override
  Future<void> execute(ToggleThemeEvent event) async {
    final next =
        bloc.state.isDarkMode ? ThemeMode.light : ThemeMode.dark;
    await commit(bloc.state.copyWith(mode: next), {ThemeGroups.mode});
  }
}
