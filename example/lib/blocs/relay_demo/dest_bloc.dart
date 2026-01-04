import 'package:juice/juice.dart';
import 'dest_state.dart';
import 'dest_events.dart';
import 'use_cases/dest_use_cases.dart';

/// Destination bloc for the relay demo.
/// Receives events from StateRelay and StatusRelay connected to SourceBloc.
class DestBloc extends JuiceBloc<DestState> {
  DestBloc()
      : super(
          DestState(),
          [
            () => UseCaseBuilder(
                  typeOfEvent: StateRelayedEvent,
                  useCaseGenerator: () => StateRelayedUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: StatusUpdatingEvent,
                  useCaseGenerator: () => StatusUpdatingUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: StatusWaitingEvent,
                  useCaseGenerator: () => StatusWaitingUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: StatusFailedEvent,
                  useCaseGenerator: () => StatusFailedUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: ClearLogEvent,
                  useCaseGenerator: () => ClearLogUseCase(),
                ),
          ],
          [],
        );
}
