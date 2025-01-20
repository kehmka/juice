import 'package:juice/juice.dart';
import '../counter_bloc.dart';
import '../counter_events.dart';

class ResetUseCase extends BlocUseCase<CounterBloc, ResetEvent> {
  @override
  Future<void> execute(ResetEvent event) async {
    final newState = bloc.state.copyWith(count: 0);
    emitUpdate(groupsToRebuild: {"counter"}, newState: newState);
  }
}
