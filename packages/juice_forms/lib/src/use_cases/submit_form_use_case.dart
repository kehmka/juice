import 'package:juice/juice.dart';

import '../field_state.dart';
import '../forms_bloc.dart';
import '../forms_events.dart';
import '../forms_state.dart';

/// Handles [SubmitFormEvent] — validate authoritatively, then submit if valid.
///
/// Does its own full sync+async pass so an in-flight debounced check can never
/// fool it. If the form is invalid, it surfaces errors and does not submit. If
/// valid but no submit handler is configured, it fails loudly (never a silent
/// no-op).
class SubmitFormUseCase extends BlocUseCase<FormsBloc, SubmitFormEvent> {
  @override
  Future<void> execute(SubmitFormEvent event) async {
    bloc.cancelAllAsyncValidation();

    final errors = await bloc.computeAllErrors();

    final fields = <String, FieldState>{
      for (final entry in bloc.state.fields.entries)
        entry.key: entry.value.copyWith(
          error: errors[entry.key],
          touched: true,
          validating: false,
        ),
    };
    final validated = bloc.state.copyWith(fields: fields);
    final fieldGroups = {
      FormsGroups.any,
      FormsGroups.valid,
      ...bloc.state.fields.keys.map(FormsGroups.field),
    };

    if (errors.values.any((e) => e != null)) {
      emitUpdate(newState: validated, groupsToRebuild: fieldGroups);
      event.succeed(false);
      return;
    }

    final handler = bloc.onSubmit;
    if (handler == null) {
      final error =
          StateError('FormsBloc.submit() called with no onSubmit handler');
      emitFailure(
        newState: validated.copyWith(
          submitting: false,
          submitError: 'No submit handler configured',
        ),
        groupsToRebuild: {FormsGroups.status},
        error: error,
      );
      event.fail(error, StackTrace.current);
      return;
    }

    emitUpdate(
      newState: validated.copyWith(submitting: true, submitError: null),
      groupsToRebuild: {...fieldGroups, FormsGroups.status},
    );

    try {
      await handler(validated.values);
      emitUpdate(
        newState: bloc.state.copyWith(submitting: false, submitted: true),
        groupsToRebuild: {FormsGroups.status},
      );
      event.succeed(true);
    } catch (e, stackTrace) {
      emitFailure(
        newState:
            bloc.state.copyWith(submitting: false, submitError: e.toString()),
        groupsToRebuild: {FormsGroups.status},
        error: e,
        errorStackTrace: stackTrace,
      );
      // The first status this event emitted was `submitting: true`, so an
      // awaiting caller is already past the status and waiting on the
      // result: it has to be failed here.
      event.fail(e, stackTrace);
    }
  }
}
