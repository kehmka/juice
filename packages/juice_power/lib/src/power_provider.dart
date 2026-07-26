import 'package:flutter/foundation.dart';

/// How the device is currently drawing power.
enum BatteryStatus {
  /// Not yet determined, or the platform declines to say.
  unknown,

  /// Running off the battery — no external power.
  discharging,

  /// External power connected and the battery is filling.
  charging,

  /// External power connected and the battery is at capacity.
  full,

  /// External power connected but not charging (iOS reports this when the
  /// device is plugged in yet deliberately holding its charge — optimized
  /// charging, a thermal hold, or a source too weak to gain).
  connectedNotCharging,
}

/// A point-in-time reading of the device's power situation.
@immutable
class PowerSnapshot {
  /// How the device is drawing power.
  final BatteryStatus status;

  /// Remaining charge, 0–100.
  ///
  /// `null` when the platform will not report it — notably the iOS Simulator,
  /// which answers -1. A consumer gating work on a level MUST treat `null` as
  /// "unknown" and not as "empty"; see [PowerState.isAtOrBelow], which refuses
  /// rather than guesses.
  final int? percent;

  /// Whether the OS power saver is on (iOS Low Power Mode, Android Battery
  /// Saver), or `null` when the platform will not say.
  ///
  /// When true, this is the keeper telling the device, system-wide, to stop
  /// doing expensive things. Treat it as an instruction, not a hint.
  ///
  /// Nullable for the same reason as [percent], and a sharper one: `false` is
  /// the PERMISSIVE answer, so a guessed `false` silently grants permission to
  /// burn power on a device that may have been asking to stop.
  final bool? saverOn;

  const PowerSnapshot({
    this.status = BatteryStatus.unknown,
    this.percent,
    this.saverOn,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PowerSnapshot &&
          other.status == status &&
          other.percent == percent &&
          other.saverOn == saverOn;

  @override
  int get hashCode => Object.hash(status, percent, saverOn);

  @override
  String toString() =>
      'PowerSnapshot($status, percent: $percent, saver: $saverOn)';
}

/// Vendor seam for battery and charging state.
///
/// `PowerBloc` depends on this interface, never on a platform plugin — which is
/// what makes it testable without a device: inject a fake provider whose
/// [changes] stream and [check] result you control. Every meaningful
/// transition in this package (unplugged, saver switched on, charge crossing a
/// threshold) is a real event on a real device and a one-line push in a test.
///
/// The default implementation is `BatteryPlusProvider`.
abstract class PowerProvider {
  /// Stream of power changes from the underlying source.
  ///
  /// Platforms signal *status* changes (plugged/unplugged) readily and *level*
  /// changes hardly at all, so a provider is not expected to emit on every
  /// percentage point. `PowerBloc` polls [check] to close that gap.
  Stream<PowerSnapshot> get changes;

  /// One-shot current reading.
  Future<PowerSnapshot> check();

  /// Release any resources held by the provider.
  Future<void> dispose();
}
