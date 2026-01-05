import 'package:juice/juice.dart';
import '../features_showcase_bloc.dart';
import '../features_showcase_events.dart';

/// Increments the counter with skipIfSame deduplication.
///
/// Demonstrates: emitUpdate with skipIfSame parameter to prevent
/// duplicate state emissions when the value hasn't changed.
class IncrementUseCase
    extends BlocUseCase<FeaturesShowcaseBloc, ShowcaseIncrementEvent> {
  @override
  Future<void> execute(ShowcaseIncrementEvent event) async {
    final newCount = bloc.state.counter + 1;

    // Using skipIfSame: true means if the counter somehow stayed the same,
    // we wouldn't emit (in this case it will always change, but it demonstrates the API)
    emitUpdate(
      newState: bloc.state.copyWith(
        counter: newCount,
        activityLog: [
          ...bloc.state.activityLog,
          'Counter incremented to $newCount',
        ],
      ),
      groupsToRebuild: {'counter', 'activity'},
      skipIfSame: true,
    );
  }
}
