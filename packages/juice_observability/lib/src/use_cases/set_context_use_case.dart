import 'package:juice/juice.dart';

import '../observability_bloc.dart';
import '../observability_events.dart';

/// Handles [SetContextEvent] — set a custom context key/value across reporters.
class SetContextUseCase extends BlocUseCase<ObservabilityBloc, SetContextEvent> {
  @override
  Future<void> execute(SetContextEvent event) async {
    await bloc.fanOut((r) => r.setContext(event.key, event.value));
  }
}
