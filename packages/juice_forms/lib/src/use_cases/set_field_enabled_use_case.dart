import 'package:juice/juice.dart';

import '../forms_bloc.dart';
import '../forms_events.dart';
import '../forms_state.dart';

/// Handles [SetFieldEnabledEvent] — toggle a field's interactability.
class SetFieldEnabledUseCase
    extends BlocUseCase<FormsBloc, SetFieldEnabledEvent> {
  @override
  Future<void> execute(SetFieldEnabledEvent event) async {
    final field = bloc.state.fields[event.name];
    if (field == null || field.enabled == event.enabled) return;

    final next = bloc.state.copyWith(
      fields: {
        ...bloc.state.fields,
        event.name: field.copyWith(enabled: event.enabled),
      },
    );
    emitUpdate(
      newState: next,
      groupsToRebuild: {FormsGroups.field(event.name), FormsGroups.any},
    );
  }
}
