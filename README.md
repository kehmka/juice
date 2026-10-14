![Juice Logo](https://stateofplay.blob.core.windows.net/juice/juice_droplet_medium.png)

# Juice

[![pub package](https://img.shields.io/pub/v/juice.svg)](https://pub.dev/packages/juice)
[![License: MIT](https://img.shields.io/badge/license-MIT-purple.svg)](LICENSE)

Juice is a lifecycle-aware Flutter application framework built around use-case driven blocs, explicit ownership, and targeted rebuilds. It is designed for apps where teams need more than local state management: auth/session lifecycles, cached networking, routing, background work, scoped cleanup, and predictable UI updates.

## Canonical Package Layout

The canonical implementation lives in [`packages/juice`](packages/juice). This repository root is the workspace and documentation hub.

Primary packages:

- [`juice`](packages/juice): core framework
- [`juice_storage`](packages/juice_storage): storage, TTL cache, secure persistence
- [`juice_network`](packages/juice_network): fetch, retry, coalescing, interceptors
- [`juice_routing`](packages/juice_routing): declarative routing and guards
- [`juice_auth`](packages/juice_auth): authentication lifecycle

## Why It Exists

Juice is most valuable when an app needs coordinated behavior across:

- app-lifetime blocs vs feature-lifetime blocs vs widget-owned blocs
- long-running async workflows with cancellation and cleanup
- targeted rebuilds instead of broad widget churn
- cross-bloc coordination without scattering service-locator code through UI
- packaged infrastructure blocs for storage, networking, routing, and auth

If you only need simple local state or straightforward CRUD screens, mainstream lighter-weight state tools are usually enough. Juice is aimed at the next tier of app complexity.

## Core Concepts

- **Use-case driven blocs**: business logic lives in dedicated use cases, not large widget callbacks
- **Lifecycle ownership**: `BlocScope` supports `permanent`, `feature`, and `leased` lifecycles
- **Targeted rebuilds**: rebuild groups let widgets opt into only the state changes they care about. Measured against bloc and Riverpod in [`benchmarks/`](benchmarks/RESULTS.md): 1 build and 0 selector calls per update (Riverpod's provider-per-cell family matches those counts), groups tie Riverpod's select and family forms per frame on a Mac and a clock-pinned iPhone and lead bloc's BlocSelector, untargeted defaults ~2.5×. Sequential dispatch is under bloc's on both machines since 2.0.0 — the table below
- **Status-aware state**: `StreamStatus` separates persistent state from transient states like waiting, failure, and canceling
- **Cross-bloc orchestration**: event subscriptions, state relays, and status relays are first-class patterns

## Performance against bloc and Riverpod

Measured in [`benchmarks/`](benchmarks/RESULTS.md) (bloc 9.2.1 / flutter_bloc 9.1.1, flutter_riverpod 3.4.3; §16 Mac, §17 iPhone 17 Pro Max with the clock pinned; both on Flutter 3.44.4, a drift against the 3.47.5 pin):

| | Juice, release default | Juice, every telemetry record built | bloc | Riverpod |
|---|---:|---:|---:|---:|
| **Dispatch**, sequential, µs per update, Mac | **0.73** | 1.00 | 1.04 | 0.42 |
| **Dispatch**, sequential, µs per update, iPhone | **0.63** | 0.88 | 1.03 | 0.41 |
| **Dispatch**, burst (fire all, await the last), Mac | 1.94 | 1.85 | **0.83** | 0.71 |
| **Frame**, 1 of 1,000 widgets updated, p50 µs, iPhone | **399** (groups) | — | 447 (BlocSelector) | 399 (family) / 398 (select) |
| **Frame**, 50 of 1,000 updated, p50 µs, iPhone | **699** (groups) / 692 (JuiceSelector + groups) | — | 751 (BlocSelector) | 804 (family) / 840 (select) |

- **Dispatch, sequential**: with nothing built — the release default — a Juice send is under bloc's by 30% on the Mac and 39% on the phone; with the full telemetry built it ties bloc (ranges overlap on both machines). In **burst** bloc leads: its event stream drains a backlog cheaper than Juice's awaited use cases (1.94 vs 0.83 µs on the Mac; a tie by range on the phone). Riverpod is faster than both and will stay so: a notifier method is a synchronous call with no event queue and no use case, so it is the floor for that shape, not a like-for-like dispatch.
- **Frames**: the tuned Juice and Riverpod forms are one band — Juice groups and Riverpod's provider-per-cell family within 0.5% on the Mac and 0.0% on the phone; bloc's BlocSelector trails that band by 18% on the Mac and 10% on the phone. Where the scenario is built to hurt groups (50 of 1,000 updated) Juice's two forms lead BlocSelector by 7% and Riverpod select by 17% on the phone, and the Juice and Riverpod forms tie on the Mac.
- **Rebuild counts** are deterministic and identical: one build per update for every tuned form, with Juice and Riverpod's family needing no selector run per consumer.
- Every number is the median of repeated rounds with its range; the harness declares a tie when ranges overlap. The pinned-toolchain run is still to be taken on a pinned machine.

## Quick Example

```dart
class CounterState extends BlocState {
  final int count;

  const CounterState({this.count = 0});

  CounterState copyWith({int? count}) {
    return CounterState(count: count ?? this.count);
  }
}

class IncrementEvent extends EventBase {}

class IncrementUseCase extends BlocUseCase<CounterBloc, IncrementEvent> {
  @override
  Future<void> execute(IncrementEvent event) async {
    emitUpdate(
      newState: bloc.state.copyWith(count: bloc.state.count + 1),
      groupsToRebuild: {'counter'},
    );
  }
}

class CounterBloc extends JuiceBloc<CounterState> {
  CounterBloc()
      : super(
          const CounterState(),
          [
            () => UseCaseBuilder(
                  typeOfEvent: IncrementEvent,
                  useCaseGenerator: () => IncrementUseCase(),
                  concurrency: EventConcurrency.sequential,
                ),
          ],
        );
}
```

## Installation

```yaml
dependencies:
  juice: ^2.0.0
```

## Start Here

- Read the package README in [`packages/juice/README.md`](packages/juice/README.md).
- Start with the standalone examples in [`packages/juice_examples`](packages/juice_examples).
- Treat the root [`example`](example) app as a framework showcase, not the primary onboarding path.

Recommended first-time evaluation order:

1. `notes_app`: lifecycle ownership, storage, rebuild groups, autosave
2. `social_feed`: fetch/caching/coalescing
3. `dashboard`: auth + routing guards
4. `ecommerce`: package composition across the ecosystem

## For AI coding agents

Juice is barely represented in training data, so the repo ships its own AI
guide ([AGENTS.md](AGENTS.md)) and a per-package AI card at
`packages/<pkg>/doc/LLM.md`. For a project that *uses* Juice, the same
material installs as a Claude Code plugin whose skill triggers on any Juice
code:

```
/plugin marketplace add kehmka/juice
/plugin install juice@juice
```

The skill is `/juice:juice`; its `references/` are synced copies of the
guide and every card (`tool/sync_skill.sh`).

## Release Notes

This workspace now treats `packages/juice` as the single source of truth for the core framework. The release also tightens package metadata, improves example positioning, and shifts the public story toward lifecycle-aware application architecture rather than generic state management alone.
