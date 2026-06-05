import 'package:juice/juice.dart';

import '../forms_bloc.dart';
import '../forms_events.dart';
import '../forms_state.dart';

/// Handles [UnregisterFieldEvent] — remove a field at runtime.
class UnregisterFieldUseCase
    extends BlocUseCase<FormsBloc, UnregisterFieldEvent> {
  @override
  Future<void> execute(UnregisterFieldEvent event) async {
    if (!bloc.state.fields.containsKey(event.name)) return;

    bloc.removeFieldConfig(event.name);

    final wasValid = bloc.state.isValid;
    final fields = {...bloc.state.fields}..remove(event.name);
    final next = bloc.state.copyWith(fields: fields);

    final groups = {FormsGroups.fields, FormsGroups.any};
    if (next.isValid != wasValid) groups.add(FormsGroups.valid);

    emitUpdate(newState: next, groupsToRebuild: groups);
  }
}
