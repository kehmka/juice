import 'connectivity_provider.dart';
import 'providers/connectivity_plus_provider.dart';

/// Configuration for [ConnectivityBloc].
class ConnectivityConfig {
  /// The connectivity source. Defaults to [ConnectivityPlusProvider].
  ///
  /// Pass a fake here in tests to drive transitions without a device.
  final ConnectivityProvider provider;

  /// Quiet period a change must hold before it is applied.
  ///
  /// Networks flap; debouncing prevents consumers from thrashing on rapid
  /// interface changes. Default: 500ms.
  final Duration debounce;

  ConnectivityConfig({
    ConnectivityProvider? provider,
    this.debounce = const Duration(milliseconds: 500),
  }) : provider = provider ?? ConnectivityPlusProvider();
}
