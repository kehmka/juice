import 'package:juice/juice.dart';

import '../power_bloc.dart';
import '../power_events.dart';

/// Handles [InitializePowerEvent].
///
/// Stores the config, subscribes to the provider, starts the level poll, then
/// emits an immediate first reading — so a consumer that boots and immediately
/// asks "may I run?" gets the truth rather than [PowerState.initial], whose
/// `unknown` status reads as not-plugged-in.
class InitializePowerUseCase
    extends BlocUseCase<PowerBloc, InitializePowerEvent> {
  @override
  Future<void> execute(InitializePowerEvent event) async {
    bloc.configure(event.config);
    bloc.startListening();
    bloc.startPolling();

    final snapshot = await bloc.provider.check();
    bloc.send(PowerChangedEvent(snapshot));
  }
}
