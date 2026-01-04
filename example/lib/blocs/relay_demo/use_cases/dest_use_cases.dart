import 'package:juice/juice.dart';
import '../dest_bloc.dart';
import '../dest_events.dart';
import '../dest_state.dart';

class StateRelayedUseCase extends BlocUseCase<DestBloc, StateRelayedEvent> {
  @override
  Future<void> execute(StateRelayedEvent event) async {
    final entry = RelayLogEntry(
      message: 'Counter changed to ${event.counter}',
      source: 'StateRelay',
    );

    emitUpdate(
      newState: bloc.state.addLogEntry(entry),
      groupsToRebuild: {'dest'},
    );
  }
}

class StatusUpdatingUseCase extends BlocUseCase<DestBloc, StatusUpdatingEvent> {
  @override
  Future<void> execute(StatusUpdatingEvent event) async {
    final entry = RelayLogEntry(
      message: 'Updating - counter: ${event.counter}',
      source: 'StatusRelay',
    );

    emitUpdate(
      newState: bloc.state.addLogEntry(entry),
      groupsToRebuild: {'dest'},
    );
  }
}

class StatusWaitingUseCase extends BlocUseCase<DestBloc, StatusWaitingEvent> {
  @override
  Future<void> execute(StatusWaitingEvent event) async {
    final entry = RelayLogEntry(
      message: 'Waiting (async in progress)...',
      source: 'StatusRelay',
    );

    emitUpdate(
      newState: bloc.state.addLogEntry(entry),
      groupsToRebuild: {'dest'},
    );
  }
}

class StatusFailedUseCase extends BlocUseCase<DestBloc, StatusFailedEvent> {
  @override
  Future<void> execute(StatusFailedEvent event) async {
    final entry = RelayLogEntry(
      message: 'Failed: ${event.errorMessage ?? "Unknown error"}',
      source: 'StatusRelay',
    );

    emitUpdate(
      newState: bloc.state.addLogEntry(entry),
      groupsToRebuild: {'dest'},
    );
  }
}

class ClearLogUseCase extends BlocUseCase<DestBloc, ClearLogEvent> {
  @override
  Future<void> execute(ClearLogEvent event) async {
    emitUpdate(
      newState: bloc.state.clearLog(),
      groupsToRebuild: {'dest'},
    );
  }
}
