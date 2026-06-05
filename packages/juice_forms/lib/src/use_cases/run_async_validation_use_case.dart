import 'package:juice/juice.dart';

import '../forms_bloc.dart';
import '../forms_events.dart';
import '../forms_state.dart';

/// Handles [RunAsyncValidationEvent] — a debounced async check fired.
///
/// Guards staleness twice: if the field's token changed before we start, or
/// changed during the await (the user typed again), the result is dropped so
/// an old answer never overwrites a newer value's state.
class RunAsyncValidationUseCase
    extends BlocUseCase<FormsBloc, RunAsyncValidationEvent> {
  @override
  Future<void> execute(RunAsyncValidationEvent event) async {
    final name = event.name;
    if (!bloc.isCurrentToken(name, event.token)) return;

    final validator = bloc.asyncValidatorFor(name);
    final field = bloc.state.fields[name];
    if (validator == null || field == null) return;

    final result = await validator(field.value, bloc.state.values);

    // The field may have changed while we awaited — drop the stale result.
    if (!bloc.isCurrentToken(name, event.token)) return;

    final current = bloc.state.fields[name];
    if (current == null) return;

    final wasValid = bloc.state.isValid;
    final next = bloc.state.copyWith(
      fields: {
        ...bloc.state.fields,
        name: current.copyWith(error: result, validating: false),
      },
    );
    final groups = {FormsGroups.field(name), FormsGroups.any};
    if (next.isValid != wasValid) groups.add(FormsGroups.valid);
    emitUpdate(newState: next, groupsToRebuild: groups);
  }
}
