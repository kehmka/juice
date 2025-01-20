import 'package:juice/juice.dart';
import '../counter_bloc.dart';
import '../counter_events.dart';

class IncrementUseCase extends BlocUseCase<CounterBloc, IncrementEvent> {
  @override
  Future<void> execute(IncrementEvent event) async {
    final newState = bloc.state.copyWith(count: bloc.state.count + 1);
    emitUpdate(groupsToRebuild: {"counter"}, newState: newState);
  }
}
