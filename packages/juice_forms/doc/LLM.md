---
card_schema: "1.0"
package: juice_forms
version: 0.1.0
requires:
  juice: ">=1.4.0"
updated: 2026-06-09
---

# juice_forms — AI card

> Form state as a bloc: fields, sync + async validation, a submit lifecycle, and
> **per-field selective rebuilds**. No vendor seam — behavior is injected as
> validators + a submit handler. Read repo `AGENTS.md` for the Juice mental model
> + gotchas.

## Purpose

**Owns:** each field's value, validation result, and touched/validating/enabled
flags, plus submit status (submitting/submitted/error).
**Does NOT own:** rendering, input widgets, or layout — consumers bind their own
inputs. State is **data only**; validators/async/debounce/submit handler live on
the bloc config, never in state.

## When to use

Any form where you want validity-driven submit gating, cross-field rules, async
checks (e.g. "is this username taken?"), and minimal rebuilds (typing in one
field doesn't rebuild the others). It's a feature bloc with no platform SDK.

## Install

```yaml
dependencies:
  juice_forms: ^0.1.0
```

## Construct

No seam to implement. `withConfig` stores the submit handler and registers the
initial fields:

```dart
final form = FormsBloc.withConfig(FormsConfig(
  fields: [
    FieldConfig(name: 'email', validators: [Validators.required(), Validators.email()]),
    FieldConfig(name: 'username',
      validators: [Validators.required()],
      asyncValidator: (v, _) async => await api.taken(v as String) ? 'Taken' : null,
      asyncDebounce: const Duration(milliseconds: 300)),
  ],
  onSubmit: (values) => api.signUp(values),   // null → submit fails LOUDLY
));
form.change('email', 'a@b.com');
form.submit();
```

## API

```dart
void register(FieldConfig config);   void unregister(String name);
void change(String name, Object? value);
void touch(String name);             void setEnabled(String name, bool enabled);
void validate();   // full sync+async pass, mark all touched
void submit();     // validate then run handler if valid
void reset();      // restore initial values, clear status
T? value<T>(String name);            // typed read of a field's value
```

`FieldConfig(name, initialValue, validators, asyncValidator, asyncDebounce,
enabled)`. Built-in `Validators`: `required`, `minLength`, `maxLength`, `email`,
`matches(otherField)` (cross-field), `all([...])`.

## Events

| Event | Effect |
|---|---|
| `InitializeFormsEvent(config)` | store handler, register initial fields |
| `RegisterFieldEvent(config)` | add a field at runtime |
| `UnregisterFieldEvent(name)` | remove a field + cancel its async |
| `ChangeFieldEvent(name, value)` | set value, sync-validate now, arm debounced async |
| `TouchFieldEvent(name)` | mark touched (blur) |
| `SetFieldEnabledEvent(name, enabled)` | toggle interactable |
| `RunAsyncValidationEvent(name, token)` *internal* | debounced async fired; token-guarded |
| `ValidateFormEvent` | full pass, mark all touched |
| `SubmitFormEvent` | validate, then run handler if valid |
| `ResetFormEvent` | restore initial values, clear submit status |

## State

```dart
class FieldState {            // data only — no behavior
  Object? value; Object? initialValue; String? error;  // error null = valid
  bool touched; bool validating; bool enabled;
  bool get valid;             // error == null (never-validated ⇒ valid)
  bool get dirty;             // value != initialValue
}
class FormsState {            // BlocState
  Map<String, FieldState> fields;  // insertion-ordered
  bool submitting; String? submitError; bool submitted;
  bool get isValid; bool get isDirty; bool get isValidating;
  Map<String, Object?> get values;  // name → value snapshot
}
```

## Rebuild groups

| Group | Emitted when |
|---|---|
| `FormsGroups.field(name)` → `form:field:<name>` | that field changed (dynamic per-name) |
| `FormsGroups.any` → `form:any` | any field changed (whole-form widgets) |
| `FormsGroups.valid` → `form:valid` | overall validity **flipped** (not every keystroke) |
| `FormsGroups.status` → `form:status` | submit lifecycle (submitting/submitted/error) |
| `FormsGroups.fields` → `form:fields` | a field was registered/unregistered |

`FormsGroups.all = {any, valid, status, fields}` (per-field is dynamic). A
widget that binds several field groups (`{field('street'), field('city')}`)
forms a *section* tier and rebuilds when any member changes — set-intersection
matching, no extra API.

## Concurrency

Use cases run with the default `concurrent` mode. Async validation is made
race-safe by a **monotonic per-field token** plus a debounce timer, both held on
the bloc (`_token` / `_debounce`). Every `change` bumps the token and re-arms
the debounce; `RunAsyncValidationEvent` checks `isCurrentToken` **before and
after** the await, so a stale async answer never overwrites a newer value's
state. `validate()`/`submit()` call `cancelAllAsyncValidation()` then do their
own awaited pass (`computeAllErrors`) — never fooled by an in-flight check.

## Recipes

```dart
// 1. Per-field input — rebuilds ONLY when this field changes
class EmailField extends StatelessJuiceWidget<FormsBloc> {
  EmailField({super.key}) : super(groups: {FormsGroups.field('email')});
  @override Widget onBuild(BuildContext c, StreamStatus s) {
    final f = bloc.state.fields['email']!;
    return TextField(
      onChanged: (v) => bloc.change('email', v),
      onSubmitted: (_) => bloc.touch('email'),
      decoration: InputDecoration(errorText: f.touched ? f.error : null),
    );
  }
}

// 2. Submit button gated on validity — rebuilds only on a validity FLIP
class SubmitButton extends StatelessJuiceWidget<FormsBloc> {
  SubmitButton({super.key}) : super(groups: {FormsGroups.valid, FormsGroups.status});
  @override Widget onBuild(BuildContext c, StreamStatus s) => ElevatedButton(
    onPressed: bloc.state.isValid && !bloc.state.submitting ? bloc.submit : null,
    child: Text(bloc.state.submitting ? 'Saving…' : 'Sign up'));
}

// 3. Cross-field rule
FieldConfig(name: 'confirm', validators: [Validators.matches('password')]);
```

## Testing

Headless (no widgets) — drive the API, assert state and emitted group sets:

```dart
final form = FormsBloc.withConfig(FormsConfig(
  fields: [FieldConfig(name: 'email', validators: [Validators.email()])],
  onSubmit: (v) async => submitted = v));
await settle();                          // Future.delayed(20ms)
form.change('email', 'bad'); await settle();
expect(form.state.fields['email']!.error, isNotNull);
form.change('email', 'a@b.com'); await settle();
expect(form.state.isValid, isTrue);
form.submit(); await settle();
expect(form.state.submitted, isTrue);
// Stale async: change twice fast; only the latest token's result applies.
```

## Failure modes

- `change`/`touch` on an **unregistered** field → throws `StateError` (a value
  for an unknown field is a programming error, not silently absorbed).
- `submit()` invalid → surfaces errors, touches all, does **not** submit.
- `submit()` valid but **no `onSubmit`** → `emitFailure` with
  `submitError: 'No submit handler configured'` — never a silent no-op.
- `onSubmit` throws → `submitError = e.toString()`, `submitting=false`.
- `close()` cancels all debounce timers.

## Anti-patterns

- ❌ Putting validators / async / debounce in state — they live in `FieldConfig`
  on the bloc; state stays a pure value.
- ❌ Trusting `state.isValid` as authoritative before a pass — a never-validated
  field reports valid; call `validate()`/`submit()` for the real check.
- ❌ Binding a field widget to `FormsGroups.any` — use `field(name)` so other
  fields' keystrokes don't rebuild it.
- ❌ Calling `change` for a field you never `register`ed — it throws.
- ❌ Relying on a debounced async result after a newer change — it's dropped by
  the token guard.

## Invariants

- **Selective rebuild:** a change emits only `field(name)` + `any` (+ `valid`
  on a validity flip); `valid` never churns per keystroke.
- **Latest-change-wins async:** token-guarded before and after the await.
- **Authoritative submit/validate:** own awaited sync+async pass, async cancelled
  first.
- **Fail-loud submit:** no handler / handler throw → `submitError`, never silent.

## See also

`SPEC.md` (validation/selective-refresh) · `README.md` (narrative) · repo
`AGENTS.md` (framework).
