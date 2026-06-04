import 'package:juice/juice.dart';

import 'theme_config.dart';

/// Base class for theme events.
abstract class ThemeEvent extends EventBase {
  @override
  String toString() => runtimeType.toString();
}

/// Configure persistence and load the saved selection (or defaults).
class InitializeThemeEvent extends ThemeEvent {
  final ThemeConfig config;
  InitializeThemeEvent({required this.config});
}

/// Set the theme mode explicitly.
class SetThemeModeEvent extends ThemeEvent {
  final ThemeMode mode;
  SetThemeModeEvent(this.mode);
}

/// Flip between light and dark (system → dark).
class ToggleThemeEvent extends ThemeEvent {}

/// Set (or clear, with `null`) the named flavor.
class SetFlavorEvent extends ThemeEvent {
  final String? flavor;
  SetFlavorEvent(this.flavor);
}
