import 'package:juice/juice.dart';

import '../field_state.dart';
import '../forms_bloc.dart';
import '../forms_events.dart';
import '../forms_state.dart';

/// Handles [ResetFormEvent] — restore every field to its initial value and
/// clear submit status.
class ResetFormUseCase extends BlocUseCase<FormsBloc, ResetFormEvent> {
  @override
  Future<void> execute(ResetFormEvent event) async {
    bloc.cancelAllAsyncValidation();

    final fields = <String, FieldState>{
      for (final cfg in bloc.fieldConfigs)
        cfg.name: FieldState(
          value: cfg.initialValue,
          initialValue: cfg.initialValue,
          enabled: cfg.enabled,
        ),
    };

    emitUpdate(
      newState: FormsState(fields: fields),
      groupsToRebuild: {
        FormsGroups.any,
        FormsGroups.valid,
        FormsGroups.status,
        FormsGroups.fields,
        ...fields.keys.map(FormsGroups.field),
      },
    );
  }
}
