import 'package:juice/juice.dart';

import 'power_config.dart';
import 'power_provider.dart';

/// Base class for power events.
abstract class PowerEvent extends EventBase {
  @override
  String toString() => runtimeType.toString();
}

/// Initialize the bloc: configure the provider, start listening, start polling.
class InitializePowerEvent extends PowerEvent {
  final PowerConfig config;
  InitializePowerEvent({required this.config});
}

/// Internal: a new power reading is available (from the provider stream, the
/// level poll, or a manual check).
class PowerChangedEvent extends PowerEvent {
  final PowerSnapshot snapshot;
  PowerChangedEvent(this.snapshot);
}

/// Manually re-read the current power situation.
class CheckPowerEvent extends PowerEvent {}
