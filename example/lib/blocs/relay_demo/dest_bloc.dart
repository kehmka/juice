import 'package:juice/juice.dart';
import 'dest_state.dart';
import 'dest_events.dart';
import 'source_bloc.dart';
import 'source_state.dart';
import 'use_cases/dest_use_cases.dart';

/// Destination bloc for the reactions demo.
///
/// It follows [SourceBloc] with three reactions, attached in its own
/// constructor and owned by it. Each says which change of the source's
/// STATE it means; none looks at the status kind — the source carries
/// "busy" and "failed" in its state.
class DestBloc extends JuiceBloc<DestState> {
  DestBloc()
      : super(
          DestState(),
          [
            () => UseCaseBuilder(
                  typeOfEvent: CounterChangedEvent,
                  useCaseGenerator: () => CounterChangedUseCase(),
                  concurrency: EventConcurrency.sequential,
                ),
            () => UseCaseBuilder(
                  typeOfEvent: SourceBusyEvent,
                  useCaseGenerator: () => SourceBusyUseCase(),
                  concurrency: EventConcurrency.sequential,
                ),
            () => UseCaseBuilder(
                  typeOfEvent: SourceFailedEvent,
                  useCaseGenerator: () => SourceFailedUseCase(),
                  concurrency: EventConcurrency.sequential,
                ),
            () => UseCaseBuilder(
                  typeOfEvent: ClearLogEvent,
                  useCaseGenerator: () => ClearLogUseCase(),
                  concurrency: EventConcurrency.sequential,
                ),
          ],
          [],
        ) {
    // changes: the selected value is no longer == to what it was. An
    // emission that leaves the counter alone sends nothing.
    react(Reaction<SourceBloc, SourceState>.changes(
      (source) => source.counter,
      send: (source) => CounterChangedEvent(counter: source.counter),
      atAttach: AtAttach.skip, // log changes from now on
    ));

    // becomes: the predicate went from false to true — once per async
    // operation, not once per emission while it runs.
    react(Reaction<SourceBloc, SourceState>.becomes(
      (source) => source.isProcessing,
      send: (_) => SourceBusyEvent(),
      atAttach: AtAttach.skip,
    ));

    react(Reaction<SourceBloc, SourceState>.becomes(
      (source) => source.errorMessage != null,
      send: (source) => SourceFailedEvent(errorMessage: source.errorMessage),
      atAttach: AtAttach.skip,
    ));
  }
}
