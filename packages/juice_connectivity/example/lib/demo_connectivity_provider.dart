import 'package:juice/juice.dart';
import 'package:juice_connectivity/juice_connectivity.dart';

/// A self-contained [ConnectivityProvider] that cycles through connection
/// states on a timer, so the demo runs with no device or real network.
///
/// Implementing [ConnectivityProvider] is the framework's intended seam — this
/// is the same pattern a real adapter (or a custom reachability source) uses.
class DemoConnectivityProvider implements ConnectivityProvider {
  final _ctrl = StreamController<ConnectivitySnapshot>.broadcast();
  Timer? _timer;

  static const _cycle = [
    ConnectivitySnapshot(type: ConnectionType.wifi),
    ConnectivitySnapshot(type: ConnectionType.cellular),
    ConnectivitySnapshot(type: ConnectionType.none),
  ];
  int _i = 0;

  DemoConnectivityProvider() {
    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      _i = (_i + 1) % _cycle.length;
      _ctrl.add(_cycle[_i]);
    });
  }

  @override
  Stream<ConnectivitySnapshot> get changes => _ctrl.stream;

  @override
  Future<ConnectivitySnapshot> check() async => _cycle[_i];

  @override
  Future<void> dispose() async {
    _timer?.cancel();
    await _ctrl.close();
  }
}
