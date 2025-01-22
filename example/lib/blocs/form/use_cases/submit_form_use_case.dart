import 'package:juice/juice.dart';
import '../form.dart';

class SubmitFormUseCase extends BlocUseCase<FormBloc, SubmitFormEvent> {
  @override
  Future<void> execute(SubmitFormEvent event) async {
    emitUpdate(
      groupsToRebuild: const {"form"},
      newState: bloc.state.copyWith(
          isSubmitting: true, submissionMessage: "Submitting the message"),
    );

    await Future.delayed(const Duration(seconds: 2)); // Simulate API call

    emitUpdate(
      groupsToRebuild: const {"form"},
      newState: bloc.state.copyWith(
        isSubmitting: false,
        submissionMessage: "Form submitted successfully!",
      ),
    );
  }
}
