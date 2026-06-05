import 'field_config.dart';
import 'forms_validators.dart';

/// Configures a `FormsBloc`: the fields it starts with and how a submit is
/// handled. Fields can also be registered/unregistered at runtime.
class FormsConfig {
  /// Fields the form starts with. May be empty for a fully-dynamic form.
  final List<FieldConfig> fields;

  /// Called with the validated values on a successful submit. Throw to surface
  /// `submitError`. If null, submitting fails loudly (no silent no-op).
  final SubmitHandler? onSubmit;

  const FormsConfig({
    this.fields = const [],
    this.onSubmit,
  });
}
