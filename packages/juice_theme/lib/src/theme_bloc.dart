import 'package:juice/juice.dart';

import 'theme_config.dart';
import 'theme_events.dart';
import 'theme_persistence.dart';
import 'theme_state.dart';
import 'use_cases/initialize_theme_use_case.dart';
import 'use_cases/set_flavor_use_case.dart';
import 'use_cases/set_theme_mode_use_case.dart';
import 'use_cases/toggle_theme_use_case.dart';

/// Bloc that owns the app's theme selection (mode + optional flavor).
///
/// Persists through a [ThemePersistence] seam, so it is testable without real
/// storage. Feed `bloc.state.mode` to `MaterialApp.themeMode`.
///
/// ```dart
/// final theme = ThemeBloc.withConfig(ThemeConfig(
///   persistence: StorageThemePersistence(storageBloc),
/// ));
/// ```
class ThemeBloc extends JuiceBloc<ThemeState> {
  late ThemeConfig _config;

  ThemeBloc()
      : super(
          ThemeState.initial,
          [
            () => UseCaseBuilder(
                  typeOfEvent: InitializeThemeEvent,
                  useCaseGenerator: () => InitializeThemeUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: SetThemeModeEvent,
                  useCaseGenerator: () => SetThemeModeUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: ToggleThemeEvent,
                  useCaseGenerator: () => ToggleThemeUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: SetFlavorEvent,
                  useCaseGenerator: () => SetFlavorUseCase(),
                ),
          ],
        );

  /// Create and initialize in one step.
  factory ThemeBloc.withConfig(ThemeConfig config) {
    final bloc = ThemeBloc();
    bloc.send(InitializeThemeEvent(config: config));
    return bloc;
  }

  /// Store config during initialization.
  void configure(ThemeConfig config) => _config = config;

  /// The persistence seam (null = in-memory only).
  ThemePersistence? get persistence => _config.persistence;

  // === Convenience ===

  /// Set the theme mode.
  void setMode(ThemeMode mode) => send(SetThemeModeEvent(mode));

  /// Flip light⇄dark.
  void toggle() => send(ToggleThemeEvent());

  /// Set or clear the named flavor.
  void setFlavor(String? flavor) => send(SetFlavorEvent(flavor));
}
