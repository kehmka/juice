import 'power_provider.dart';
import 'providers/battery_plus_provider.dart';

/// Configuration for [PowerBloc].
class PowerConfig {
  /// The power source. Defaults to [BatteryPlusProvider].
  ///
  /// Pass a fake here in tests to drive transitions without a device.
  final PowerProvider provider;

  /// How often to re-read the charge level.
  ///
  /// Platforms broadcast plugged/unplugged promptly but do not stream the
  /// percentage, so a consumer gating on a level would otherwise act on a
  /// number frozen at the last status change. Polling closes that gap. A
  /// minute is far finer than a battery moves and costs a single cheap
  /// platform call.
  ///
  /// [Duration.zero] disables polling — correct when nothing you do depends on
  /// the level, only on whether power is connected.
  final Duration pollInterval;

  PowerConfig({
    PowerProvider? provider,
    this.pollInterval = const Duration(minutes: 1),
  }) : provider = provider ?? BatteryPlusProvider();
}
