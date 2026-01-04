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
                ),
            () => UseCaseBuilder(
                  typeOfEvent: DecrementSourceEvent,
                  useCaseGenerator: () => DecrementSourceUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: SimulateAsyncEvent,
                  useCaseGenerator: () => SimulateAsyncUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: SimulateErrorEvent,
                  useCaseGenerator: () => SimulateErrorUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: ResetSourceEvent,
                  useCaseGenerator: () => ResetSourceUseCase(),
                ),
          ],
          [],
        );
}
