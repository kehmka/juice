/// Battery and charging state as a Juice bloc.
///
/// `PowerBloc` exposes whether the device is plugged in, how much charge
/// remains, and whether the OS power saver is on, sourced through a swappable
/// [PowerProvider] seam (default: `BatteryPlusProvider`). Because the bloc
/// depends on the provider interface rather than a platform plugin, it is
/// fully testable without a device.
///
/// It is an **ambient signal**, in the same family as `juice_connectivity`:
/// it reports the device's situation and never decides what to do about it.
/// Whether expensive work may run on battery is the consumer's policy, because
/// only the consumer knows how expensive the work is and how badly the keeper
/// wants it.
///
/// ```dart
/// final power = PowerBloc.withConfig(PowerConfig());
///
/// class ChargeBadge extends StatelessJuiceWidget<PowerBloc> {
///   ChargeBadge({super.key}) : super(groups: {PowerGroups.source});
///   @override
///   Widget onBuild(BuildContext context, StreamStatus status) =>
///       Icon(bloc.state.isPluggedIn ? Icons.power : Icons.battery_std);
/// }
/// ```
library juice_power;

export 'src/power_bloc.dart';
export 'src/power_config.dart';
export 'src/power_events.dart';
export 'src/power_provider.dart';
export 'src/power_state.dart';
export 'src/providers/battery_plus_provider.dart';
