import 'package:battery_plus/battery_plus.dart';
import 'package:juice/juice.dart';

import '../power_provider.dart';

/// Default [PowerProvider] backed by `battery_plus`.
///
/// Deliberately logic-light: it maps the plugin's results to [PowerSnapshot]
/// and nothing more. All meaningful behavior lives in `PowerBloc`, which is
/// tested with a fake provider — this adapter is verified by inspection and a
/// one-time on-device run.
class BatteryPlusProvider implements PowerProvider {
  final Battery _battery;

  BatteryPlusProvider({Battery? battery}) : _battery = battery ?? Battery();

  /// `battery_plus` streams the STATUS but never the level or the saver, so
  /// each status change is enriched with a fresh read of both. Level polling
  /// (for changes that arrive with no status change at all) is `PowerBloc`'s
  /// job, via [check].
  @override
  Stream<PowerSnapshot> get changes =>
      _battery.onBatteryStateChanged.asyncMap(_enrich);

  @override
  Future<PowerSnapshot> check() async =>
      _enrich(await _battery.batteryState);

  @override
  Future<void> dispose() async {}

  Future<PowerSnapshot> _enrich(BatteryState state) async => PowerSnapshot(
        status: _toStatus(state),
        percent: await _level(),
        saverOn: await _saver(),
      );

  /// A percentage, or null when the platform will not say.
  ///
  /// The iOS Simulator answers -1 and some Android devices throw outright.
  /// Both mean UNKNOWN, and unknown is reported AS unknown — a consumer gating
  /// heavy work on a low battery must not be handed a fabricated 0 (which
  /// would stop everything) or a fabricated 100 (which would stop nothing).
  /// `PowerState.isAtOrBelow` then refuses to compare rather than guessing.
  Future<int?> _level() async {
    try {
      final level = await _battery.batteryLevel;
      if (level < 0 || level > 100) {
        // -1 on the Simulator. Not an error, but not a level either.
        JuiceLoggerConfig.logger.log(
            'BatteryPlusProvider: battery level out of range ($level) — '
            'reporting unknown');
        return null;
      }
      return level;
    } catch (e, st) {
      JuiceLoggerConfig.logger.logError(
          'BatteryPlusProvider: battery level unreadable — reporting unknown',
          e,
          st);
      return null;
    }
  }

  /// Whether the OS power saver is on.
  ///
  /// Unknown is reported as unknown for the same reason as the level, and for
  /// a sharper one: `false` here means "the keeper has NOT asked to conserve",
  /// which is the permissive answer. Guessing it would silently grant
  /// permission to burn power on a device that may well have been begging to
  /// stop — precisely the wrong direction to be wrong in. A consumer decides
  /// what null means for its own work.
  Future<bool?> _saver() async {
    try {
      return await _battery.isInBatterySaveMode;
    } catch (e, st) {
      JuiceLoggerConfig.logger.logError(
          'BatteryPlusProvider: power-saver mode unreadable — reporting '
          'unknown',
          e,
          st);
      return null;
    }
  }

  BatteryStatus _toStatus(BatteryState state) => switch (state) {
        BatteryState.charging => BatteryStatus.charging,
        BatteryState.discharging => BatteryStatus.discharging,
        BatteryState.full => BatteryStatus.full,
        BatteryState.connectedNotCharging =>
          BatteryStatus.connectedNotCharging,
        BatteryState.unknown => BatteryStatus.unknown,
      };
}
