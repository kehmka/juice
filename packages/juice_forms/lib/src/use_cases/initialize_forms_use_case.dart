import 'package:juice/juice.dart';

import '../field_state.dart';
import '../forms_bloc.dart';
import '../forms_events.dart';
import '../forms_state.dart';

/// Handles [InitializeFormsEvent] — apply config and register initial fields.
class InitializeFormsUseCase
    extends BlocUseCase<FormsBloc, InitializeFormsEvent> {
  @override
  Future<void> execute(InitializeFormsEvent event) async {
    bloc.configureForm(event.config);

    final fields = <String, FieldState>{};
    for (final cfg in event.config.fields) {
      bloc.configureField(cfg);
      fields[cfg.name] = FieldState(
        value: cfg.initialValue,
        initialValue: cfg.initialValue,
        enabled: cfg.enabled,
      );
    }

    emitUpdate(
      newState: bloc.state.copyWith(fields: fields),
      groupsToRebuild: {FormsGroups.fields, FormsGroups.valid},
    );
  }
}
