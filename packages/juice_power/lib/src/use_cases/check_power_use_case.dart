import 'package:juice/juice.dart';

import '../power_bloc.dart';
import '../power_events.dart';

/// Handles [CheckPowerEvent] — a one-shot re-read, used both by the level poll
/// and by a consumer that wants to be sure before starting expensive work.
class CheckPowerUseCase extends BlocUseCase<PowerBloc, CheckPowerEvent> {
  @override
  Future<void> execute(CheckPowerEvent event) async {
    final snapshot = await bloc.provider.check();
    bloc.send(PowerChangedEvent(snapshot));
  }
}
