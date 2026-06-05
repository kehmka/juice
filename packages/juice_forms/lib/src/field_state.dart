/// Sentinel so [FieldState.copyWith] can distinguish "not passed" from an
/// explicit `null` — both `value` and `error` are legitimately nullable.
const Object _unset = Object();

/// Immutable, data-only state for a single form field.
///
/// Holds no behavior — validators, async checks, and debounce live on the
/// bloc's field config, not here. This keeps the state a pure value.
class FieldState {
  /// Current value (any type; read via `bloc.value<T>(name)`).
  final Object? value;

  /// The value the field was registered/reset with — basis for [dirty].
  final Object? initialValue;

  /// Validation error message, or null when valid.
  final String? error;

  /// Whether the user has interacted with and left the field (blur).
  /// Drives "show the error only after the user has touched it" UX.
  final bool touched;

  /// Whether an async validation is currently in flight.
  final bool validating;

  /// Whether the field is interactable.
  final bool enabled;

  const FieldState({
    this.value,
    this.initialValue,
    this.error,
    this.touched = false,
    this.validating = false,
    this.enabled = true,
  });

  /// No known error. Note: a field that has never been validated reports valid
  /// (error is null) — call `validate()`/`submit()` for a full pass.
  bool get valid => error == null;

  /// Value differs from [initialValue] (by `==`).
  bool get dirty => value != initialValue;

  FieldState copyWith({
    Object? value = _unset,
    Object? initialValue = _unset,
    Object? error = _unset,
    bool? touched,
    bool? validating,
    bool? enabled,
  }) {
    return FieldState(
      value: identical(value, _unset) ? this.value : value,
      initialValue:
          identical(initialValue, _unset) ? this.initialValue : initialValue,
      error: identical(error, _unset) ? this.error : error as String?,
      touched: touched ?? this.touched,
      validating: validating ?? this.validating,
      enabled: enabled ?? this.enabled,
    );
  }

  @override
  String toString() =>
      'FieldState($value, error: $error, touched: $touched, validating: $validating)';
}
