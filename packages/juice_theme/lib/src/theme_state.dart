import 'package:juice/juice.dart';

/// Rebuild groups emitted by [ThemeBloc].
abstract final class ThemeGroups {
  /// Theme mode (light/dark/system) changed.
  static const mode = 'theme:mode';

  /// Named flavor changed.
  static const flavor = 'theme:flavor';

  static const all = {mode, flavor};
}

/// Immutable theme-selection state.
///
/// Owns the *selection* (mode + optional flavor key), not the `ThemeData` —
/// the app maps this to its themes and feeds [mode] to `MaterialApp.themeMode`.
class ThemeState extends BlocState {
  /// Light / dark / system.
  final ThemeMode mode;

  /// Optional named theme flavor (e.g. 'ocean'), for multi-theme apps.
  final String? flavor;

  const ThemeState({
    this.mode = ThemeMode.system,
    this.flavor,
  });

  static const initial = ThemeState();

  /// The mode is explicitly dark. (For the *resolved* brightness under
  /// `system`, read `MediaQuery.platformBrightnessOf` in the UI.)
  bool get isDarkMode => mode == ThemeMode.dark;

  /// The mode is explicitly light.
  bool get isLightMode => mode == ThemeMode.light;

  /// The mode follows the platform.
  bool get isSystemMode => mode == ThemeMode.system;

  ThemeState copyWith({
    ThemeMode? mode,
    String? flavor,
    bool clearFlavor = false,
  }) {
    return ThemeState(
      mode: mode ?? this.mode,
      flavor: clearFlavor ? null : (flavor ?? this.flavor),
    );
  }

  @override
  String toString() => 'ThemeState($mode, flavor: $flavor)';
}
