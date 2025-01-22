import 'package:juice/juice.dart';
import '../counter_bloc.dart';
import '../counter_events.dart';

class DecrementUseCase extends BlocUseCase<CounterBloc, DecrementEvent> {
  @override
  Future<void> execute(DecrementEvent event) async {
    final newState = bloc.state.copyWith(count: bloc.state.count - 1);
    emitUpdate(groupsToRebuild: {"counter"}, newState: newState);
  }
}
