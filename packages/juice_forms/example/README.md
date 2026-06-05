# juice_forms example

A sign-up form built with Juice primitives only — no controllers, no notifiers,
no `setState`.

Demonstrates the point of the package: **each field widget binds only its own
rebuild group** (`FormsGroups.field(name)`), so typing in one field never
rebuilds the others. The submit button binds `FormsGroups.valid` +
`FormsGroups.status`, so it reacts to validity and submit state but not to every
keystroke.

Includes:
- sync validation (`required`, `email`, `minLength`)
- a debounced **async** username check (`'admin'` is "taken")
- a `validating` spinner per field
- submit lifecycle (disabled until valid → spinner → success)

## Run

```bash
flutter run
```
