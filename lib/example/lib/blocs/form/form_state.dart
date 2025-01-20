import 'package:juice/juice.dart';

class ExampleFormState extends BlocState {
  final bool isSubmitting;
  final String submissionMessage;

  ExampleFormState({this.isSubmitting = false, this.submissionMessage = ""});

  ExampleFormState copyWith({bool? isSubmitting, String? submissionMessage}) {
    return ExampleFormState(
      isSubmitting: isSubmitting ?? this.isSubmitting,
      submissionMessage: submissionMessage ?? this.submissionMessage,
    );
  }
}
