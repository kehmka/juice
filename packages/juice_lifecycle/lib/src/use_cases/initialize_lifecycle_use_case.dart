import 'package:juice/juice.dart';

import '../lifecycle_bloc.dart';
import '../lifecycle_events.dart';

/// Handles [InitializeLifecycleEvent] — configure, start listening, emit the
/// current phase.
class InitializeLifecycleUseCase
    extends BlocUseCase<LifecycleBloc, InitializeLifecycleEvent> {
  @override
  Future<void> execute(InitializeLifecycleEvent event) async {
    bloc.configure(event.config);
    bloc.startListening();
    bloc.send(LifecycleChangedEvent(bloc.provider.current));
  }
}
