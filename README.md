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
- **Targeted rebuilds**: rebuild groups let widgets opt into only the state changes they care about
- **Status-aware state**: `StreamStatus` separates persistent state from transient states like waiting, failure, and canceling
- **Cross-bloc orchestration**: event subscriptions, state relays, and status relays are first-class patterns

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
                ),
          ],
        );
}
```

## Installation

```yaml
dependencies:
  juice: ^1.4.0
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

## Release Notes

This workspace now treats `packages/juice` as the single source of truth for the core framework. The release also tightens package metadata, improves example positioning, and shifts the public story toward lifecycle-aware application architecture rather than generic state management alone.
