# Ecosystem comparison, September 2026 — raw reports

Five independent deep-dives, run in parallel on 2026-09-16 against the same
baseline (AGENTS.md, ROADMAP.md, the core source) and the same output schema.
Each was told to grep Juice's source before claiming a gap and to cite the
version and URL of everything it read about the other side.

| Report | Family | Versions read |
|---|---|---|
| [bloc.md](bloc.md) | bloc / flutter_bloc / bloc_concurrency / hydrated_bloc / replay_bloc / bloc_test / bloc_lint | bloc 9.2.1, flutter_bloc 9.1.1, bloc_concurrency 0.3.0, hydrated_bloc 11.0.0, replay_bloc 0.3.0, bloc_test 10.0.0, bloc_lint 0.4.2 |
| [riverpod.md](riverpod.md) | Riverpod 3 | riverpod 3.4.3, riverpod_generator 4.0.9, riverpod_lint 3.1.9, riverpod_devtools 1.1.2 |
| [signals.md](signals.md) | signals / preact_signals / solidart / state_beacon / BlocSignal / flutter_hooks | signals 7.1.0, preact_signals 7.0.0, solidart 2.8.6, state_beacon 3.1.2, BlocSignal 1.3.0 |
| [others.md](others.md) | mobx / redux / async_redux / stacked / rearch / get_it / injectable / fpdart / command_it / elementary / very_good_cli | as cited inline |
| [dx.md](dx.md) | developer experience: codegen, lint hosts, DevTools, test harnesses, scaffolding, docs, migration tooling, AI-agent affordances | as cited inline |

The synthesis, adjudication of every "Juice lacks" claim against source, and
the ranked candidate list are in [../../ECOSYSTEM_COMPARISON_2026_09.md](../../ECOSYSTEM_COMPARISON_2026_09.md).
Treat the raw reports as evidence with dates: they are not maintained.
