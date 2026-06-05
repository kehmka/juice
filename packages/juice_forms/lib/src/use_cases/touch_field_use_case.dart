import 'package:juice/juice.dart';

import '../forms_bloc.dart';
import '../forms_events.dart';
import '../forms_state.dart';

/// Handles [TouchFieldEvent] — mark a field touched (user focused then left).
class TouchFieldUseCase extends BlocUseCase<FormsBloc, TouchFieldEvent> {
  @override
  Future<void> execute(TouchFieldEvent event) async {
    final field = bloc.state.fields[event.name];
    if (field == null || field.touched) return;

    final next = bloc.state.copyWith(
      fields: {...bloc.state.fields, event.name: field.copyWith(touched: true)},
    );
    emitUpdate(
      newState: next,
      groupsToRebuild: {FormsGroups.field(event.name), FormsGroups.any},
    );
  }
}
