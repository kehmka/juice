/// App theme selection as a Juice bloc.
///
/// `ThemeBloc` owns the theme *selection* — [ThemeMode] mode plus an optional
/// named flavor — and persists it through a swappable [ThemePersistence] seam
/// (default: `StorageThemePersistence`). It owns the selection, not the
/// `ThemeData`: feed `bloc.state.mode` to `MaterialApp.themeMode` and map
/// `bloc.state.flavor` to your own themes.
///
/// ```dart
/// final theme = ThemeBloc.withConfig(
///   ThemeConfig(persistence: StorageThemePersistence(storageBloc)),
/// );
///
/// class App extends StatelessJuiceWidget<ThemeBloc> {
///   App({super.key}) : super(groups: {ThemeGroups.mode});
///   @override
///   Widget onBuild(BuildContext context, StreamStatus status) => MaterialApp(
///         themeMode: bloc.state.mode,
///         theme: lightTheme, darkTheme: darkTheme,
///         home: const Home(),
///       );
/// }
/// ```
library juice_theme;

export 'package:flutter/material.dart' show ThemeMode;

export 'src/providers/storage_theme_persistence.dart';
export 'src/theme_bloc.dart';
export 'src/theme_config.dart';
export 'src/theme_events.dart';
export 'src/theme_persistence.dart';
export 'src/theme_state.dart';
