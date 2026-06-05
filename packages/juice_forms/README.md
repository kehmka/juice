# juice_forms

Form state — fields, sync/async validation, and **per-field selective
rebuilds** — as a [Juice](https://pub.dev/packages/juice) bloc.

[![pub package](https://img.shields.io/pub/v/juice_forms.svg)](https://pub.dev/packages/juice_forms)
[![License: MIT](https://img.shields.io/badge/license-MIT-purple.svg)](LICENSE)

## Why

A form is a pile of fields that each change independently. Rebuilding the whole
form on every keystroke is wasteful and janky. `juice_forms` gives each field
its **own rebuild group**, so a widget only re-renders when *its* field changes —
no `setState`, no controllers, no notifiers.

## Install

```yaml
dependencies:
  juice_forms: ^0.1.0
```

## Selective refresh — the core idea

Each field owns a rebuild group: `FormsGroups.field('email')`. Bind a widget to
just that group and it rebuilds **only** when email changes:

```dart
class EmailInput extends StatelessJuiceWidget<FormsBloc> {
  EmailInput({super.key}) : super(groups: {FormsGroups.field('email')});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    final field = bloc.state.fields['email'];
    return TextField(
      onChanged: (v) => bloc.change('email', v),
      onTapOutside: (_) => bloc.touch('email'),
      decoration: InputDecoration(
        labelText: 'Email',
        errorText: field?.touched == true ? field?.error : null,
      ),
    );
  }
}
```

Typing in the password field never rebuilds this one. Whole-form widgets bind
`FormsGroups.any` instead; the submit button binds `FormsGroups.valid`.

## Create a form

```dart
final form = FormsBloc.withConfig(FormsConfig(
  fields: [
    FieldConfig(
      name: 'username',
      validators: [Validators.required(), Validators.minLength(3)],
      asyncValidator: (value, values) async {
        final taken = await api.isUsernameTaken(value);
        return taken ? 'Already taken' : null;
      },
    ),
    FieldConfig(name: 'email', validators: [Validators.required(), Validators.email()]),
    FieldConfig(name: 'password', validators: [Validators.required(), Validators.minLength(8)]),
  ],
  onSubmit: (values) => api.signUp(values),
));

form.change('email', 'a@b.com');
form.submit();
```

## Validation

- **Sync** — `String? Function(value, values)`, run in order, first error wins.
  `values` is every field's value, so cross-field rules work:
  `Validators.matches('password')`.
- **Async** — runs *after* sync passes, **debounced** (`asyncDebounce`), with
  **stale results dropped**: if the field changes again before the check
  returns, the old answer is discarded (latest value wins). `field.validating`
  is true while in flight.
- `submit()` and `validate()` do their own full **awaited** pass, so submit is
  never fooled by an in-flight debounced check.

Built-in `Validators`: `required`, `minLength`, `maxLength`, `email`, `matches`,
`all`.

## State

`FormsState` is **data-only** — validators live on the bloc's config, not in
state.

| Field / getter | Meaning |
|---|---|
| `fields` | `Map<String, FieldState>` |
| `isValid` | no field reports an error |
| `isDirty` | any field differs from its initial value |
| `isValidating` | any async check in flight |
| `values` | `name → value` snapshot |
| `submitting` / `submitted` / `submitError` | submit lifecycle |

Each `FieldState`: `value`, `error`, `touched`, `validating`, `enabled`,
derived `valid`/`dirty`. Read a value with `bloc.value<String>('email')`.

> A never-validated field reports `valid` (its error is null). Call
> `validate()`/`submit()` for an authoritative full pass.

## Dynamic fields

```dart
form.register(FieldConfig(name: 'coupon'));
form.unregister('coupon');
```

## What it owns / doesn't

**Owns:** field values, validation results, submit status — with selective
rebuild groups. **Does NOT own:** rendering, input widgets, or layout. You bind
your own `TextField`/`Switch` (the example shows it). There is no vendor seam —
forms touch no platform SDK; the injected pieces are your validators and submit
handler.

## License

MIT License — see [LICENSE](LICENSE).
