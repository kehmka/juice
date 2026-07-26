import 'package:juice/juice.dart';
import 'package:juice_power/juice_power.dart';

/// A [PowerProvider] with no platform underneath, so the demo runs anywhere —
/// including a simulator, where a real battery level is unavailable.
///
/// It also drains: one point every two seconds, which is what makes the level
/// group and the poll visible in a demo that would otherwise sit still.
class DemoPowerProvider implements PowerProvider {
  final _ctrl = StreamController<PowerSnapshot>.broadcast();
  Timer? _drain;
  PowerSnapshot _current = const PowerSnapshot(
    status: BatteryStatus.discharging,
    percent: 62,
    saverOn: false,
  );

  DemoPowerProvider() {
    _drain = Timer.periodic(const Duration(seconds: 2), (_) {
      final p = _current.percent;
      if (p == null || _current.status != BatteryStatus.discharging) return;
      // Silent, like a real battery: no status change, so only the bloc's
      // poll notices. Pulling the level down past a gate is the whole point.
      _current = PowerSnapshot(
          status: _current.status,
          percent: p > 0 ? p - 1 : 0,
          saverOn: _current.saverOn);
    });
  }

  @override
  Stream<PowerSnapshot> get changes => _ctrl.stream;

  @override
  Future<PowerSnapshot> check() async => _current;

  @override
  Future<void> dispose() async {
    _drain?.cancel();
    await _ctrl.close();
  }

  /// Plug the imaginary cable in or out.
  void togglePlug() => _push(_current.status == BatteryStatus.discharging
      ? BatteryStatus.charging
      : BatteryStatus.discharging);

  /// Flip the imaginary power saver.
  void toggleSaver() {
    _current = PowerSnapshot(
        status: _current.status,
        percent: _current.percent,
        saverOn: !(_current.saverOn ?? false));
    _ctrl.add(_current);
  }

  /// Make the level unreadable, as a Simulator or a throwing device does.
  void loseTheLevel() {
    _current = PowerSnapshot(
        status: _current.status, percent: null, saverOn: _current.saverOn);
    _ctrl.add(_current);
  }

  void _push(BatteryStatus status) {
    _current = PowerSnapshot(
        status: status, percent: _current.percent, saverOn: _current.saverOn);
    _ctrl.add(_current);
  }
}
