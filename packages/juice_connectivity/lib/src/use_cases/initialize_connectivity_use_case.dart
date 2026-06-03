import 'package:juice/juice.dart';

import '../connectivity_bloc.dart';
import '../connectivity_events.dart';

/// Handles [InitializeConnectivityEvent].
///
/// Stores the config, starts the (debounced) provider subscription, then emits
/// an immediate initial reading via a one-shot check.
class InitializeConnectivityUseCase
    extends BlocUseCase<ConnectivityBloc, InitializeConnectivityEvent> {
  @override
  Future<void> execute(InitializeConnectivityEvent event) async {
    bloc.configure(event.config);
    bloc.startListening();

    // Immediate (undebounced) initial reading so consumers have state at once.
    final snapshot = await bloc.provider.check();
    bloc.send(ConnectivityChangedEvent(snapshot));
  }
}
