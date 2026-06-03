/// Network reachability as a Juice bloc.
///
/// `ConnectivityBloc` exposes online/offline status and the active connection
/// type, sourced through a swappable [ConnectivityProvider] seam (default:
/// `ConnectivityPlusProvider`). Because the bloc depends on the provider
/// interface rather than a platform plugin, it is fully testable without a
/// device.
///
/// ```dart
/// final connectivity = ConnectivityBloc.withConfig(ConnectivityConfig());
///
/// class Banner extends StatelessJuiceWidget<ConnectivityBloc> {
///   Banner({super.key}) : super(groups: {ConnectivityGroups.status});
///   @override
///   Widget onBuild(BuildContext context, StreamStatus status) =>
///       bloc.state.isOffline ? const OfflineBanner() : const SizedBox.shrink();
/// }
/// ```
library juice_connectivity;

export 'src/connectivity_bloc.dart';
export 'src/connectivity_config.dart';
export 'src/connectivity_events.dart';
export 'src/connectivity_provider.dart';
export 'src/connectivity_state.dart';
export 'src/providers/connectivity_plus_provider.dart';
