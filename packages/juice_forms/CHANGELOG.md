# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2026-06-10

From dogfooding (Glean DOGFOOD.md F3).

### Added

- **Awaitable validation/submit** — `Future<bool> validateNow()` and
  `Future<bool> submitNow()`: the use case completes the future with the
  outcome (`isValid` / handler-succeeded), so "validate, then save" flows no
  longer need a settle-delay after the fire-and-forget `validate()`.
  `ValidateFormEvent`/`SubmitFormEvent` gain an optional `completion` Completer.
  Additive and backward-compatible.

## [0.1.0] - 2026-05-28

### Added

- Initial release.
- **`FormsBloc`** — form state for a set of fields, with **per-field selective
  rebuilds**: a widget bound to `FormsGroups.field('email')` rebuilds only when
  that field changes.
- **Dynamic fields** — register/unregister fields at runtime.
- **Sync + async validation** — `Validator` and `AsyncValidator`; async runs
  after sync passes, debounced, with stale results dropped (latest change wins).
- **`Validators`** — `required`, `minLength`, `maxLength`, `email`, `matches`
  (cross-field), `all`.
- **Submit lifecycle** — `submit()` does its own awaited validation pass, then
  runs the injected `SubmitHandler`; surfaces `submitError`, marks `submitted`.
  A submit with no handler fails loudly.
- **State** — data-only `FormsState`/`FieldState` (value/error/touched/
  validating/enabled) with derived `isValid`/`isDirty`/`values`. Validators live
  on the bloc config, never in state.
- **Rebuild groups** — `form:field:<name>`, `form:any`, `form:valid`,
  `form:status`, `form:fields`.
