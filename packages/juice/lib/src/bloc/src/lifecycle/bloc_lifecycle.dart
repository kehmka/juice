/// Defines the lifecycle behavior for a bloc instance.
///
/// The lifecycle determines when a bloc is created and disposed,
/// enabling semantic correctness rather than cache-based eviction.
enum BlocLifecycle {
  /// Lives for entire app lifetime. Never auto-disposed.
  ///
  /// Use for app-wide blocs that should persist throughout the
  /// application's lifecycle.
  ///
  /// Examples: AuthBloc, SettingsBloc, AppBloc, ThemeBloc
  permanent,

  /// Lives for a feature/flow. Disposed when FeatureScope ends.
  ///
  /// Use for blocs that belong to a specific feature or user flow
  /// and should be disposed when that flow completes.
  ///
  /// Examples: CheckoutBloc, OnboardingBloc, WizardBloc
  feature,

  /// Lives while leases exist. Auto-disposed when last lease releases.
  ///
  /// Use for UI-specific blocs that should only exist while
  /// widgets are actively using them.
  ///
  /// Examples: FormBloc, SearchBloc, ItemDetailBloc
  leased,
}
