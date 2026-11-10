import 'package:juice/juice.dart';
import '../dest_bloc.dart';
import '../dest_events.dart';
import '../dest_state.dart';

class CounterChangedUseCase extends BlocUseCase<DestBloc, CounterChangedEvent> {
  @override
  Future<void> execute(CounterChangedEvent event) async {
    final entry = ReactionLogEntry(
      message: 'Counter changed to ${event.counter}',
      form: ReactionLogEntry.changes,
    );

    emitUpdate(
      newState: bloc.state.addLogEntry(entry),
      groupsToRebuild: {'dest'},
    );
  }
}

class SourceBusyUseCase extends BlocUseCase<DestBloc, SourceBusyEvent> {
  @override
  Future<void> execute(SourceBusyEvent event) async {
    final entry = ReactionLogEntry(
      message: 'Source became busy (async in progress)...',
      form: ReactionLogEntry.becomes,
    );

    emitUpdate(
      newState: bloc.state.addLogEntry(entry),
      groupsToRebuild: {'dest'},
    );
  }
}

class SourceFailedUseCase extends BlocUseCase<DestBloc, SourceFailedEvent> {
  @override
  Future<void> execute(SourceFailedEvent event) async {
    final entry = ReactionLogEntry(
      message: 'Source failed: ${event.errorMessage ?? "Unknown error"}',
      form: ReactionLogEntry.becomes,
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
