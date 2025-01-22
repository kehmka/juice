import 'package:juice/juice.dart';

abstract class FormEvent extends EventBase {}

class SubmitFormEvent extends FormEvent {
  final Map<String, String> formData;

  SubmitFormEvent(this.formData);
}
