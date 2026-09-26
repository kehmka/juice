# Changelog

## [0.2.0] - 2026-09-26

Ported from `custom_lint` (unmaintained; built on the deprecated legacy
analyzer-plugin API) to Dart's official `analysis_server_plugin` (0.3.23,
analyzer 14.4.0). **The rules are now reported by the stock `dart analyze`
CLI** — the custom_lint version only reported through `dart run
custom_lint` and the IDE. (`flutter analyze` on Flutter 3.47.5 still does
not show them: its LSP client exits before plugin results arrive.)

- **Breaking — enablement changed.** Drop the `custom_lint` and
  `juice_lint` dev dependencies and the `analyzer: plugins: - custom_lint`
  entry; enable with a top-level `plugins: juice_lint:` section in
  `analysis_options.yaml` (a version, `path:`, or git source). Disable a
  rule under `plugins: juice_lint: diagnostics:`; suppress inline with
  `// ignore: juice_lint/<rule>`.
- The three 0.1.0 rules ported: `juice_generic_event`,
  `juice_mutable_state_field`, `juice_behavior_in_state`. Semantics are
  unchanged except one precision fix: `juice_generic_event` no longer
  flags an **abstract or sealed** generic base (e.g. juice's own
  `ResultEvent<TResult>`), which is never sent itself.
- First quick fix: `juice_mutable_state_field` → make the field `final`.
- New rules (warnings):
  - `juice_send_in_build` — `bloc.send`/`sendCancellable` directly in a
    `build`/`onBuild` body (closures such as `onPressed:` are fine).
  - `juice_lease_in_build` — `BlocScope.lease`/`leaseAsync` directly in a
    `build`/`onBuild` body.
  - `juice_stale_read_across_await` — a `bloc.state` snapshot taken before
    an `await` and used in an emit's `newState:` after it (AGENTS §4; the
    heuristic is documented in the README).
  - `juice_missing_concurrency_mode` (**opt-in** lint rule) —
    `UseCaseBuilder(...)` / `UseCaseBuilder.typed(...)` without
    `concurrency:`. Enable with `juice_missing_concurrency_mode: true`.
- Not shipped: a nullable-`copyWith` sentinel rule (gotcha 6) — it cannot
  tell a must-be-clearable field from a set-once one, and its family-wide
  hits were set-once fields.
- Fixture suite: `example/` plants each violation behind an
  `// expect_lint:` marker; `dart run tool/check_fixtures.dart` runs
  `dart analyze` there and fails on any missing or extra diagnostic.
- Requires a Dart ≥ 3.10 SDK at analysis time (package SDK floor ^3.9.0,
  matching `analysis_server_plugin`).

## [0.1.0] - 2026-08-21

Initial release — the Juice AGENTS.md idioms as `custom_lint` rules
(BlocSignal tee-up item 1, phase 3):

- `juice_generic_event` — a generic `EventBase` subclass never matches a
  `typeOfEvent` builder (exact-runtime-type dispatch).
- `juice_mutable_state_field` — `BlocState` fields must be `final`.
- `juice_behavior_in_state` — functions, timers, subscriptions, and
  controllers belong on the bloc, not in state.

Rules scoped to `package:juice` base types; verified by an `expect_lint`
fixture suite.
