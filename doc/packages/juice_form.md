# juice_form

> Canonical specification for the juice_form companion package

## Purpose

Form handling with validation, field state management, and submission workflows.

---

## Dependencies

**External:** None

**Juice Packages:** None

---

## Architecture

### Bloc: `FormBloc<T>`

**Lifecycle:** Feature or Leased (per form instance)

### State

```dart
class FormState<T> extends BlocState {
  final Map<String, FieldState> fields;
  final FormStatus status; // idle, validating, submitting, success, error
  final T? formData;
  final FormError? error;
  final bool isDirty;
  final bool isValid;
}

class FieldState {
  final dynamic value;
  final String? error;
  final bool isTouched;
  final bool isValidating;
}
```

### Events

- `InitializeFormEvent` - Set initial values and validators
- `UpdateFieldEvent` - Update single field value
- `ValidateFieldEvent` - Validate single field
- `ValidateFormEvent` - Validate all fields
- `SubmitFormEvent` - Submit if valid
- `ResetFormEvent` - Reset to initial state

### Rebuild Groups

- `form:field:{name}` - Per-field rebuilds
- `form:status` - Overall form status
- `form:validation` - Validation state changes

---

## Open Questions

_To be discussed_
