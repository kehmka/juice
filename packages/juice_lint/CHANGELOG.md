# Changelog

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
