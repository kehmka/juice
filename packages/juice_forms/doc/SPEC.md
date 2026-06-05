# juice_forms Specification

> **Status:** Implemented (shipping).
> **Package:** `juice_forms`
> **Primary Bloc:** `FormsBloc`

## Overview

Form state for a set of fields, with **per-field selective rebuilds**, sync +
async validation, and a submit lifecycle. A feature bloc with **no vendor
seam** — forms touch no platform SDK; behavior is injected as validators and a
submit handler.

## Domain boundary

- **Owns:** each field's value, validation result, touched/validating/enabled
  flags, and submit status (submitting/submitted/error).
- **Does NOT own:** rendering, input widgets, layout. Consumers bind their own
  inputs.

## Selective refresh

The reason this package exists. Each field has a dedicated rebuild group; the
bloc emits only the groups affected by a change, so widgets bound to other
fields don't rebuild.

| Group | Emitted when |
|---|---|
| `FormsGroups.field(name)` → `form:field:<name>` | that field changed |
| `FormsGroups.any` → `form:any` | any field changed (whole-form widgets) |
| `FormsGroups.valid` → `form:valid` | overall validity **flipped** |
| `FormsGroups.status` → `form:status` | submit lifecycle changed |
| `FormsGroups.fields` → `form:fields` | a field was registered/unregistered |

`FormsGroups.all = {any, valid, status, fields}`. Per-field groups are dynamic —
reached via `field(name)`. `valid` is emitted only on an actual flip, so a
submit button bound to it doesn't churn on every keystroke.

## State (data only)

```dart
class FieldState {
  final Object? value;
  final Object? initialValue;
  final String? error;     // null = valid
  final bool touched;
  final bool validating;   // async check in flight
  final bool enabled;
  bool get valid => error == null;
  bool get dirty => value != initialValue;
}

class FormsState extends BlocState {
  final Map<String, FieldState> fields;
  final bool submitting;
  final String? submitError;
  final bool submitted;
  bool get isValid;        // no field has an error
  bool get isDirty;
  bool get isValidating;
  Map<String, Object?> get values;
}
```

Validators, async checks, debounce, and the submit handler are **not** in state —
they live in the bloc's `_configs`/`_onSubmit`. State stays a pure value.

A never-validated field reports `valid` (error is null); `validate()`/`submit()`
do an authoritative pass.

## Validation

- `Validator = String? Function(Object? value, Map<String,Object?> values)` —
  sync; `values` enables cross-field rules.
- `AsyncValidator = Future<String?> Function(value, values)` — runs only after
  sync passes.

**Async concurrency.** Each field has a monotonic token, bumped on every change.
A change arms a debounce timer (`asyncDebounce`); when it fires,
`RunAsyncValidationEvent(name, token)` runs the check. The result is applied only
if the token is still current — checked **before and after** the await — so a
stale answer never overwrites a newer value's state. `cancelAsyncValidation`
bumps the token and cancels the timer.

`computeAllErrors()` runs a full sync-then-awaited-async pass over all fields;
`validate()` and `submit()` use it so they're never fooled by an in-flight
debounced check.

## Events

| Event | Effect |
|---|---|
| `InitializeFormsEvent(config)` | store submit handler, register initial fields |
| `RegisterFieldEvent(config)` | add a field at runtime |
| `UnregisterFieldEvent(name)` | remove a field |
| `ChangeFieldEvent(name, value)` | set value, sync-validate, arm async |
| `TouchFieldEvent(name)` | mark touched |
| `SetFieldEnabledEvent(name, enabled)` | toggle enabled |
| `RunAsyncValidationEvent(name, token)` | internal — debounced async fired |
| `ValidateFormEvent` | full pass, mark all touched |
| `SubmitFormEvent` | validate, then run handler if valid |
| `ResetFormEvent` | restore initial values, clear status |

## Submit (fail-loud)

`submit()` → full awaited validation. If invalid: surface errors, touch all, do
**not** submit. If valid and a handler exists: `submitting`, await handler,
`submitted` (or `submitError` on throw). If valid but **no handler configured**:
`emitFailure` with `submitError` — never a silent no-op.

## Testing

Headless (no widgets). Covered: sync first-error/clear, cross-field matches,
**selective refresh** (asserting emitted group sets), validity-flip gating,
async validating→resolve, **stale-async-dropped**, submit valid/invalid/
no-handler/throw, submit-awaits-async, register/unregister, reset. 17 tests.

## Spec Version

| Version | Date | Status |
|---|---|---|
| 1.0 | 2026-05-28 | Implemented |
