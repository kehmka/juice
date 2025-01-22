import 'package:juice/juice.dart';
import 'counter_state.dart';
import 'counter_events.dart';
import 'use_cases/increment_use_case.dart';
import 'use_cases/decrement_use_case.dart';
import 'use_cases/reset_use_case.dart';

class CounterBloc extends JuiceBloc<CounterState> {
  CounterBloc()
      : super(
          CounterState(count: 0),
          [
            () => UseCaseBuilder(
                typeOfEvent: IncrementEvent,
                useCaseGenerator: () => IncrementUseCase()),
            () => UseCaseBuilder(
                typeOfEvent: DecrementEvent,
                useCaseGenerator: () => DecrementUseCase()),
            () => UseCaseBuilder(
                typeOfEvent: ResetEvent,
                useCaseGenerator: () => ResetUseCase()),
          ],
          [],
        );
}
