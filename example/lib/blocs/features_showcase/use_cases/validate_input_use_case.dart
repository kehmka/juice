import 'package:juice/juice.dart';
import '../features_showcase_bloc.dart';
import '../features_showcase_events.dart';

/// Validates user input and demonstrates ValidationException.
///
/// Demonstrates:
/// - ValidationException for form/input validation errors
/// - Error context with field information
/// - Typed exception handling
class ValidateInputUseCase
    extends BlocUseCase<FeaturesShowcaseBloc, ValidateInputEvent> {
  @override
  Future<void> execute(ValidateInputEvent event) async {
    final input = event.input.trim();

    try {
      // Validate the input
      if (input.isEmpty) {
        throw const ValidationException(
          'Input cannot be empty',
          field: 'message',
        );
      }

      if (input.length < 3) {
        throw const ValidationException(
          'Input must be at least 3 characters',
          field: 'message',
        );
      }

      if (input.length > 100) {
        throw const ValidationException(
          'Input cannot exceed 100 characters',
          field: 'message',
        );
      }

      // Validation passed - update the message
      emitUpdate(
        newState: bloc.state.copyWith(
          message: input,
          clearError: true,
          activityLog: [
            ...bloc.state.activityLog,
            'Message updated to: "$input"',
          ],
        ),
        groupsToRebuild: {'message', 'activity'},
      );
    } on ValidationException catch (e, stackTrace) {
      emitFailure(
        newState: bloc.state.copyWith(
          lastError: '${e.field}: ${e.message}',
          activityLog: [
            ...bloc.state.activityLog,
            'Validation failed: ${e.message}',
          ],
        ),
        groupsToRebuild: {'error', 'activity'},
        error: e,
        errorStackTrace: stackTrace,
      );
    }
  }
}
