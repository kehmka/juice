import 'package:juice/juice.dart';

import 'field_config.dart';
import 'forms_config.dart';

/// Base class for form events.
abstract class FormsEvent extends EventBase {
  @override
  String toString() => runtimeType.toString();
}

/// Apply config: store the submit handler and register the initial fields.
class InitializeFormsEvent extends FormsEvent {
  final FormsConfig config;
  InitializeFormsEvent({required this.config});
}

/// Add a field at runtime.
class RegisterFieldEvent extends FormsEvent {
  final FieldConfig config;
  RegisterFieldEvent(this.config);
}

/// Remove a field at runtime.
class UnregisterFieldEvent extends FormsEvent {
  final String name;
  UnregisterFieldEvent(this.name);
}

/// Set a field's value — runs sync validation now, schedules async (debounced).
class ChangeFieldEvent extends FormsEvent {
  final String name;
  final Object? value;
  ChangeFieldEvent(this.name, this.value);
}

/// Mark a field touched (user focused then left it).
class TouchFieldEvent extends FormsEvent {
  final String name;
  TouchFieldEvent(this.name);
}

/// Enable/disable a field.
class SetFieldEnabledEvent extends FormsEvent {
  final String name;
  final bool enabled;
  SetFieldEnabledEvent(this.name, this.enabled);
}

/// Internal: a debounced async validation fired. [token] guards staleness —
/// if the field changed since scheduling, the result is dropped.
class RunAsyncValidationEvent extends FormsEvent {
  final String name;
  final int token;
  RunAsyncValidationEvent(this.name, this.token);
}

/// Validate every field (sync + awaited async) and mark all touched.
class ValidateFormEvent extends FormsEvent {}

/// Validate all, then run the submit handler if the form is valid.
class SubmitFormEvent extends FormsEvent {}

/// Reset every field to its initial value and clear submit status.
class ResetFormEvent extends FormsEvent {}
