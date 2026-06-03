/// App lifecycle (foreground/background/resume) as a Juice bloc.
///
/// `LifecycleBloc` exposes the app's [AppLifecycle] phase through a swappable
/// [LifecycleProvider] seam (default: `WidgetsLifecycleProvider`, backed by
/// Flutter's `AppLifecycleListener`). Because the bloc depends on the provider
/// interface rather than `WidgetsBinding`, it is fully testable without a real
/// binding.
///
/// ```dart
/// final lifecycle = LifecycleBloc.withConfig(LifecycleConfig());
///
/// class Dimmer extends StatelessJuiceWidget<LifecycleBloc> {
///   Dimmer({super.key}) : super(groups: {LifecycleGroups.state});
///   @override
///   Widget onBuild(BuildContext context, StreamStatus status) =>
///       bloc.state.isForeground ? const AppBody() : const PrivacyScreen();
/// }
/// ```
library juice_lifecycle;

export 'src/lifecycle_bloc.dart';
export 'src/lifecycle_config.dart';
export 'src/lifecycle_events.dart';
export 'src/lifecycle_provider.dart';
export 'src/lifecycle_state.dart';
export 'src/providers/widgets_lifecycle_provider.dart';
