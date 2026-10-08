import 'package:juice/juice.dart';
import 'source_state.dart';
import 'source_events.dart';
import 'use_cases/source_use_cases.dart';

/// Source bloc for the relay demo.
/// This bloc's state changes will be relayed to the DestBloc.
class SourceBloc extends JuiceBloc<SourceState> {
  SourceBloc()
      : super(
          SourceState(counter: 0),
          [
            () => UseCaseBuilder(
                  typeOfEvent: IncrementSourceEvent,
                  useCaseGenerator: () => IncrementSourceUseCase(),
                  concurrency: EventConcurrency.sequential,
                ),
            () => UseCaseBuilder(
                  typeOfEvent: DecrementSourceEvent,
                  useCaseGenerator: () => DecrementSourceUseCase(),
                  concurrency: EventConcurrency.sequential,
                ),
            () => UseCaseBuilder(
                  typeOfEvent: SimulateAsyncEvent,
                  useCaseGenerator: () => SimulateAsyncUseCase(),
                  concurrency: EventConcurrency.sequential,
                ),
            () => UseCaseBuilder(
                  typeOfEvent: SimulateErrorEvent,
                  useCaseGenerator: () => SimulateErrorUseCase(),
                  concurrency: EventConcurrency.sequential,
                ),
            () => UseCaseBuilder(
                  typeOfEvent: ResetSourceEvent,
                  useCaseGenerator: () => ResetSourceUseCase(),
                  concurrency: EventConcurrency.sequential,
                ),
          ],
          [],
        );
}
