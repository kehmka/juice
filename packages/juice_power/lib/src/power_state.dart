import 'package:juice/juice.dart';

import 'power_provider.dart';

/// Rebuild groups emitted by [PowerBloc].
abstract final class PowerGroups {
  /// The device was plugged in or unplugged.
  static const source = 'power:source';

  /// The charge level moved.
  static const level = 'power:level';

  /// The OS power saver was switched on or off.
  static const saver = 'power:saver';

  static const all = {source, level, saver};
}

/// Immutable power state: how the device is drawing power, how much charge is
/// left, and whether the keeper has asked the OS to conserve.
///
/// This state REPORTS; it does not decide. Whether a given piece of work may
/// run on battery, or below some percentage, is the consumer's policy — it
/// varies by how expensive the work is and how much the keeper wants it. The
/// bloc that knows the work owns that rule; this one only knows the facts.
class PowerState extends BlocState {
  /// How the device is drawing power.
  final BatteryStatus status;

  /// Remaining charge 0–100, or `null` when the platform will not say.
  final int? percent;

  /// Whether the OS power saver is on, or `null` when the platform will not
  /// say.
  ///
  /// A consumer decides what unknown means for its own work. [saverAsked] is
  /// the reading most want.
  final bool? saverOn;

  /// When any of the above last changed.
  final DateTime? lastChangedAt;

  const PowerState({
    this.status = BatteryStatus.unknown,
    this.percent,
    this.saverOn,
    this.lastChangedAt,
  });

  /// Initial state, before the first reading.
  static const initial = PowerState();

  /// External power is connected — charging, full, or holding.
  ///
  /// `unknown` is deliberately NOT plugged in: before the first reading, and on
  /// a platform that refuses to answer, the safe reading of "is it safe to burn
  /// power?" is no.
  bool get isPluggedIn =>
      status == BatteryStatus.charging ||
      status == BatteryStatus.full ||
      status == BatteryStatus.connectedNotCharging;

  /// The device is running off its battery.
  bool get isOnBattery => status == BatteryStatus.discharging;

  /// Whether the keeper has positively asked the OS to conserve.
  ///
  /// Unknown reads as "has not asked", which is the honest reading of a signal
  /// that only ever means something when it is TRUE — and unlike a guessed
  /// `false` inside the provider, this one is a consumer-side choice made in
  /// the open, next to the work it affects.
  bool get saverAsked => saverOn == true;

  /// Whether the charge is known to be at or below [threshold].
  ///
  /// FALSE when [percent] is unknown, on purpose: an unknown level must not
  /// read as an empty one. A caller that would rather stop when it cannot tell
  /// should test `percent == null` itself and say so — the ambiguity belongs
  /// where someone can decide it, not buried in a comparison.
  bool isAtOrBelow(int threshold) => percent != null && percent! <= threshold;

  /// Sentinel distinguishing "leave [percent] alone" from "set it to null".
  ///
  /// Without this, `percent ?? this.percent` can never CLEAR the level: a
  /// device that stops reporting its charge would keep serving the last number
  /// it gave, forever, and a consumer gating on that number would act on a
  /// reading that has quietly gone stale. Unknown must be expressible.
  static const Object _unset = Object();

  PowerState copyWith({
    BatteryStatus? status,
    Object? percent = _unset,
    Object? saverOn = _unset,
    DateTime? lastChangedAt,
  }) {
    return PowerState(
      status: status ?? this.status,
      percent: identical(percent, _unset) ? this.percent : percent as int?,
      saverOn: identical(saverOn, _unset) ? this.saverOn : saverOn as bool?,
      lastChangedAt: lastChangedAt ?? this.lastChangedAt,
    );
  }

  @override
  String toString() => 'PowerState($status, percent: $percent, '
      'saver: $saverOn)';
}
