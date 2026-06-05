import 'forms_validators.dart';

/// Declares a field: its initial value plus the *behavior* (validators, async
/// check, debounce) that the bloc applies. Behavior never lives in state.
class FieldConfig {
  /// Unique field name (the key in `FormsState.fields`).
  final String name;

  /// Value the field starts (and resets) with.
  final Object? initialValue;

  /// Synchronous validators, run in order; first error wins.
  final List<Validator> validators;

  /// Optional async validator, run only after sync passes — debounced, with
  /// stale results dropped (latest change wins).
  final AsyncValidator? asyncValidator;

  /// How long to wait after the last change before firing [asyncValidator].
  /// `Duration.zero` fires on the next microtask (deterministic for tests).
  final Duration asyncDebounce;

  /// Whether the field starts interactable.
  final bool enabled;

  const FieldConfig({
    required this.name,
    this.initialValue,
    this.validators = const [],
    this.asyncValidator,
    this.asyncDebounce = const Duration(milliseconds: 300),
    this.enabled = true,
  });
}
