import 'package:juice/juice.dart';

import '../field_state.dart';
import '../forms_bloc.dart';
import '../forms_events.dart';
import '../forms_state.dart';

/// Handles [ValidateFormEvent] — full sync+async pass over every field, marking
/// all touched. Rebuilds every field widget plus `valid`.
class ValidateFormUseCase extends BlocUseCase<FormsBloc, ValidateFormEvent> {
  @override
  Future<void> execute(ValidateFormEvent event) async {
    bloc.cancelAllAsyncValidation(); // we validate authoritatively here

    final errors = await bloc.computeAllErrors();

    final fields = <String, FieldState>{
      for (final entry in bloc.state.fields.entries)
        entry.key: entry.value.copyWith(
          error: errors[entry.key],
          touched: true,
          validating: false,
        ),
    };

    emitUpdate(
      newState: bloc.state.copyWith(fields: fields),
      groupsToRebuild: {
        FormsGroups.any,
        FormsGroups.valid,
        ...bloc.state.fields.keys.map(FormsGroups.field),
      },
    );
  }
}
