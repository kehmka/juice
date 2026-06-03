import 'package:connectivity_plus/connectivity_plus.dart';

import '../connectivity_provider.dart';

/// Default [ConnectivityProvider] backed by `connectivity_plus`.
///
/// Deliberately logic-light: it only maps the plugin's interface results to
/// [ConnectivitySnapshot] (interface-state only; reachability is left `null`).
/// All meaningful behavior lives in `ConnectivityBloc`, which is tested with a
/// fake provider — this adapter is verified by inspection and a one-time
/// on-device run.
class ConnectivityPlusProvider implements ConnectivityProvider {
  final Connectivity _connectivity;

  ConnectivityPlusProvider({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity();

  @override
  Stream<ConnectivitySnapshot> get changes =>
      _connectivity.onConnectivityChanged.map(_toSnapshot);

  @override
  Future<ConnectivitySnapshot> check() async =>
      _toSnapshot(await _connectivity.checkConnectivity());

  @override
  Future<void> dispose() async {}

  ConnectivitySnapshot _toSnapshot(List<ConnectivityResult> results) =>
      ConnectivitySnapshot(type: _toType(results));

  ConnectionType _toType(List<ConnectivityResult> results) {
    if (results.isEmpty ||
        results.every((r) => r == ConnectivityResult.none)) {
      return ConnectionType.none;
    }
    if (results.contains(ConnectivityResult.wifi)) return ConnectionType.wifi;
    if (results.contains(ConnectivityResult.mobile)) {
      return ConnectionType.cellular;
    }
    if (results.contains(ConnectivityResult.ethernet)) {
      return ConnectionType.ethernet;
    }
    return ConnectionType.other;
  }
}
