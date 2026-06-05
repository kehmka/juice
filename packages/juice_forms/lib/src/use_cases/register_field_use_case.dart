import 'package:juice/juice.dart';

import '../field_state.dart';
import '../forms_bloc.dart';
import '../forms_events.dart';
import '../forms_state.dart';

/// Handles [RegisterFieldEvent] — add a field at runtime.
class RegisterFieldUseCase extends BlocUseCase<FormsBloc, RegisterFieldEvent> {
  @override
  Future<void> execute(RegisterFieldEvent event) async {
    final cfg = event.config;
    bloc.configureField(cfg);

    final field = FieldState(
      value: cfg.initialValue,
      initialValue: cfg.initialValue,
      enabled: cfg.enabled,
    );
    final wasValid = bloc.state.isValid;
    final fields = {...bloc.state.fields, cfg.name: field};
    final next = bloc.state.copyWith(fields: fields);

    final groups = {FormsGroups.fields, FormsGroups.field(cfg.name)};
    if (next.isValid != wasValid) groups.add(FormsGroups.valid);

    emitUpdate(newState: next, groupsToRebuild: groups);
  }
}
