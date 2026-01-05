import 'package:juice/juice.dart';
import '../features_showcase_bloc.dart';
import '../features_showcase_events.dart';

/// Decrements the counter.
class DecrementUseCase
    extends BlocUseCase<FeaturesShowcaseBloc, ShowcaseDecrementEvent> {
  @override
  Future<void> execute(ShowcaseDecrementEvent event) async {
    final newCount = bloc.state.counter - 1;

    emitUpdate(
      newState: bloc.state.copyWith(
        counter: newCount,
        activityLog: [
          ...bloc.state.activityLog,
          'Counter decremented to $newCount',
        ],
      ),
      groupsToRebuild: {'counter', 'activity'},
    );
  }
}
