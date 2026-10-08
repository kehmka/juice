import 'package:juice/juice.dart';

import 'features_showcase_state.dart';
import 'features_showcase_events.dart';
import 'use_cases/increment_use_case.dart';
import 'use_cases/decrement_use_case.dart';
import 'use_cases/simulate_api_use_case.dart';
import 'use_cases/validate_input_use_case.dart';
import 'use_cases/helper_use_cases.dart';

/// Bloc that showcases the new Juice features.
///
/// This bloc demonstrates:
/// - JuiceException hierarchy (NetworkException, ValidationException)
/// - FailureStatus with error context
/// - sendAndWait for awaiting event completion
/// - emitUpdate with skipIfSame for state deduplication
/// - State used with JuiceSelector for optimized rebuilds
class FeaturesShowcaseBloc extends JuiceBloc<FeaturesShowcaseState> {
  FeaturesShowcaseBloc()
      : super(
          const FeaturesShowcaseState(),
          [
            // Counter operations with skipIfSame
            () => UseCaseBuilder(
                  typeOfEvent: ShowcaseIncrementEvent,
                  useCaseGenerator: () => IncrementUseCase(),
                  concurrency: EventConcurrency.sequential,
                ),
            () => UseCaseBuilder(
                  typeOfEvent: ShowcaseDecrementEvent,
                  useCaseGenerator: () => DecrementUseCase(),
                  concurrency: EventConcurrency.sequential,
                ),
            // API simulation with JuiceException and FailureStatus error context
            () => UseCaseBuilder(
                  typeOfEvent: SimulateApiCallEvent,
                  useCaseGenerator: () => SimulateApiUseCase(),
                  concurrency: EventConcurrency.sequential,
                ),
            // Validation with ValidationException
            () => UseCaseBuilder(
                  typeOfEvent: ValidateInputEvent,
                  useCaseGenerator: () => ValidateInputUseCase(),
                  concurrency: EventConcurrency.sequential,
                ),
            // Message update with skipIfSame deduplication
            () => UseCaseBuilder(
                  typeOfEvent: UpdateMessageEvent,
                  useCaseGenerator: () => UpdateMessageUseCase(),
                  concurrency: EventConcurrency.sequential,
                ),
            // Helper use cases
            () => UseCaseBuilder(
                  typeOfEvent: ClearErrorEvent,
                  useCaseGenerator: () => ClearErrorUseCase(),
                  concurrency: EventConcurrency.sequential,
                ),
            () => UseCaseBuilder(
                  typeOfEvent: ShowcaseResetEvent,
                  useCaseGenerator: () => ResetUseCase(),
                  concurrency: EventConcurrency.sequential,
                ),
          ],
        );
}
