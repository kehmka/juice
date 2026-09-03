# juice_lint

Custom analyzer lints for the [Juice](https://pub.dev/packages/juice)
framework — the `AGENTS.md` idioms enforced as rules, so mistakes surface in
the IDE instead of at runtime.

## Rules

| Rule | Flags | Why |
| --- | --- | --- |
| `juice_generic_event` | a generic `EventBase` subclass (`Foo<T>`) | events match by EXACT runtime type, so `typeOfEvent: Foo` never fires for `Foo<T>` — a silent dead event |
| `juice_mutable_state_field` | a non-`final` instance field on a `BlocState` | state is an immutable value changed only through `copyWith`; a mutable field breaks equality diffing (`skipIfSame`) |
| `juice_behavior_in_state` | a function/`Timer`/`StreamSubscription`/`StreamController`/`*Controller`/`*Bloc` field on a `BlocState` | state holds DATA, not behavior — handles belong on the bloc or its config |

All three are `warning` severity and scoped to Juice's own base types
(`packageName: 'juice'`), so a same-named class from another package is
never touched.

## Use

```yaml
dev_dependencies:
  custom_lint: ^0.8.1
  juice_lint: ^0.1.0
```

```yaml
# analysis_options.yaml
analyzer:
  plugins:
    - custom_lint
```

Disable a rule (project-wide) under `custom_lint:` in `analysis_options.yaml`,
or inline with `// ignore: juice_generic_event`.

## Example

`example/README.md` walks each rule: the offending code, the exact warning,
and the fix, with the `AGENTS.md` idiom it encodes.

## Develop

Fixtures in `example/lib/fixtures.dart` use `// expect_lint: <code>` markers;
`cd example && dart run custom_lint` verifies every rule fires and none
over-fires.

Dogfood canary: the five `juice_examples` apps carry the plugin;
`melos run lint:juice` from the workspace root runs it across them (all
clean as of 2026-09-02; all three rules confirmed live on real app code by
planted sentinels). Note `flutter analyze` loads the plugin but does not
report its diagnostics — only `dart run custom_lint` and the IDE do.
