/// The app's lifecycle phase (mirrors Flutter's `AppLifecycleState`).
enum AppLifecycle {
  /// Visible and responding to input (foreground).
  resumed,

  /// Transitioning — visible but not focused (e.g. app switcher, call overlay).
  inactive,

  /// Not visible; running in the background.
  paused,

  /// Engine running with no attached view (e.g. about to exit).
  detached,

  /// All views hidden (Flutter 3.13+).
  hidden,
}

/// Vendor seam for app lifecycle.
///
/// `LifecycleBloc` depends on this interface, not on `WidgetsBinding`, which is
/// what makes it testable without a real binding: inject a fake whose [changes]
/// stream you drive. The default implementation is `WidgetsLifecycleProvider`.
abstract class LifecycleProvider {
  /// Stream of lifecycle changes.
  Stream<AppLifecycle> get changes;

  /// The current lifecycle phase.
  AppLifecycle get current;

  /// Release any resources held by the provider.
  Future<void> dispose();
}
