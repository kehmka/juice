import 'package:juice/juice.dart';

import 'connectivity_config.dart';
import 'connectivity_provider.dart';

/// Base class for connectivity events.
abstract class ConnectivityEvent extends EventBase {
  @override
  String toString() => runtimeType.toString();
}

/// Initialize the bloc: configure the provider and start listening.
class InitializeConnectivityEvent extends ConnectivityEvent {
  final ConnectivityConfig config;
  InitializeConnectivityEvent({required this.config});
}

/// Internal: a new connectivity reading is available (from the provider stream
/// or a manual check).
class ConnectivityChangedEvent extends ConnectivityEvent {
  final ConnectivitySnapshot snapshot;
  ConnectivityChangedEvent(this.snapshot);
}

/// Manually re-read the current connectivity.
class CheckConnectivityEvent extends ConnectivityEvent {}
