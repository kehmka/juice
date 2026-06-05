import 'package:juice/juice.dart';

import '../forms_bloc.dart';
import '../forms_events.dart';
import '../forms_state.dart';

/// Handles [ChangeFieldEvent] — set the value, run sync validation now, and
/// arm a debounced async check (latest change wins).
///
/// Emits only this field's group (+ `any`, + `valid` when overall validity
/// flips), so widgets bound to other fields never rebuild.
class ChangeFieldUseCase extends BlocUseCase<FormsBloc, ChangeFieldEvent> {
  @override
  Future<void> execute(ChangeFieldEvent event) async {
    final name = event.name;
    final current = bloc.state.fields[name];
    if (current == null) {
      // Fail loudly: a value for an unregistered field is a programming error,
      // not something to silently absorb.
      throw StateError('ChangeFieldEvent for unregistered field "$name"');
    }

    final wasValid = bloc.state.isValid;
    final values = {...bloc.state.values, name: event.value};
    final syncError = bloc.syncErrorFor(name, event.value, values);
    final willValidateAsync =
        syncError == null && bloc.asyncValidatorFor(name) != null;

    final field = current.copyWith(
      value: event.value,
      error: syncError, // null clears a prior error
      validating: willValidateAsync,
    );
    final next =
        bloc.state.copyWith(fields: {...bloc.state.fields, name: field});

    final groups = {FormsGroups.field(name), FormsGroups.any};
    if (next.isValid != wasValid) groups.add(FormsGroups.valid);
    emitUpdate(newState: next, groupsToRebuild: groups);

    // Invalidate any in-flight async; arm a new debounced check if warranted.
    if (willValidateAsync) {
      bloc.scheduleAsyncValidation(name);
    } else {
      bloc.cancelAsyncValidation(name);
    }
  }
}
