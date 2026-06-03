import 'package:juice/juice.dart';

import '../connectivity_bloc.dart';
import '../connectivity_events.dart';

/// Handles [CheckConnectivityEvent] — a one-shot manual re-read.
class CheckConnectivityUseCase
    extends BlocUseCase<ConnectivityBloc, CheckConnectivityEvent> {
  @override
  Future<void> execute(CheckConnectivityEvent event) async {
    final snapshot = await bloc.provider.check();
    bloc.send(ConnectivityChangedEvent(snapshot));
  }
}
