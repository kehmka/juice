import 'package:juice/juice.dart';

import 'field_state.dart';

/// Rebuild groups emitted by `FormsBloc`.
///
/// The per-field group is the heart of selective refresh: a widget bound to
/// `FormsGroups.field('email')` rebuilds **only** when the email field changes —
/// typing in another field never touches it. Whole-form consumers bind
/// [any] instead.
abstract final class FormsGroups {
  /// A specific field changed. `FormsGroups.field('email')` → `form:field:email`.
  static String field(String name) => 'form:field:$name';

  /// Any field changed (for widgets that render across the whole form).
  static const any = 'form:any';

  /// Overall validity flipped (drives enabling/disabling the submit button).
  static const valid = 'form:valid';

  /// Submit lifecycle changed (submitting / submitted / error).
  static const status = 'form:status';

  /// The field set changed structurally (a field was registered/unregistered).
  static const fields = 'form:fields';

  /// Form-level groups. Per-field groups are dynamic — reach them via [field].
  static const all = {any, valid, status, fields};
}

/// Immutable form state: the data of every registered field plus submit status.
class FormsState extends BlocState {
  /// Registered fields, keyed by name. Insertion order preserved.
  final Map<String, FieldState> fields;

  /// A submit is in flight.
  final bool submitting;

  /// The last submit failed with this message.
  final String? submitError;

  /// The last submit succeeded.
  final bool submitted;

  const FormsState({
    this.fields = const {},
    this.submitting = false,
    this.submitError,
    this.submitted = false,
  });

  static const initial = FormsState();

  /// No field currently reports an error. (A never-validated field counts as
  /// valid — see [FieldState.valid].)
  bool get isValid => fields.values.every((f) => f.valid);

  /// Any field differs from its initial value.
  bool get isDirty => fields.values.any((f) => f.dirty);

  /// Any field has an async validation in flight.
  bool get isValidating => fields.values.any((f) => f.validating);

  /// Snapshot of every field's value, keyed by name.
  Map<String, Object?> get values =>
      {for (final e in fields.entries) e.key: e.value.value};

  FormsState copyWith({
    Map<String, FieldState>? fields,
    bool? submitting,
    Object? submitError = _unset,
    bool? submitted,
  }) {
    return FormsState(
      fields: fields ?? this.fields,
      submitting: submitting ?? this.submitting,
      submitError: identical(submitError, _unset)
          ? this.submitError
          : submitError as String?,
      submitted: submitted ?? this.submitted,
    );
  }

  @override
  String toString() =>
      'FormsState(${fields.length} fields, valid: $isValid, submitting: $submitting, submitted: $submitted)';
}

const Object _unset = Object();
