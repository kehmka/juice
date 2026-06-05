/// A synchronous field validator. Returns an error message, or null if valid.
///
/// [values] is a snapshot of every field's value, enabling cross-field rules
/// (e.g. confirm-password checking against `values['password']`).
typedef Validator = String? Function(Object? value, Map<String, Object?> values);

/// An asynchronous field validator (e.g. "is this username taken?").
/// Runs only after sync validators pass, debounced, with stale results dropped.
typedef AsyncValidator = Future<String?> Function(
    Object? value, Map<String, Object?> values);

/// Handles a validated submit. Throw to surface `submitError`.
typedef SubmitHandler = Future<void> Function(Map<String, Object?> values);

/// A small set of common synchronous validators. Pure — no dependencies.
abstract final class Validators {
  /// Non-null and, for strings/iterables, non-empty.
  static Validator required([String message = 'Required']) {
    return (value, _) {
      if (value == null) return message;
      if (value is String && value.trim().isEmpty) return message;
      if (value is Iterable && value.isEmpty) return message;
      return null;
    };
  }

  /// String length at least [n].
  static Validator minLength(int n, [String? message]) {
    return (value, _) {
      final s = value is String ? value : '';
      return s.length < n ? (message ?? 'Must be at least $n characters') : null;
    };
  }

  /// String length at most [n].
  static Validator maxLength(int n, [String? message]) {
    return (value, _) {
      final s = value is String ? value : '';
      return s.length > n ? (message ?? 'Must be at most $n characters') : null;
    };
  }

  /// Basic email shape.
  static Validator email([String message = 'Enter a valid email']) {
    final re = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    return (value, _) {
      final s = value is String ? value : '';
      return re.hasMatch(s) ? null : message;
    };
  }

  /// Field must equal the value of [otherField] (e.g. confirm-password).
  static Validator matches(String otherField, [String message = 'Does not match']) {
    return (value, values) => value == values[otherField] ? null : message;
  }

  /// Composes validators, returning the first error.
  static Validator all(List<Validator> validators) {
    return (value, values) {
      for (final v in validators) {
        final err = v(value, values);
        if (err != null) return err;
      }
      return null;
    };
  }
}
