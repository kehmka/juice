![Juice Logo](https://stateofplay.blob.core.windows.net/juice/juice_droplet_medium.png)

# Juice

[![pub package](https://img.shields.io/pub/v/juice.svg)](https://pub.dev/packages/juice)
[![License: MIT](https://img.shields.io/badge/license-MIT-purple.svg)](LICENSE)

Juice is a lifecycle-aware Flutter application framework built around use-case driven blocs, explicit ownership, and targeted rebuilds.

## What It Solves

Juice is aimed at apps that need stronger structure than simple local state tools provide:

- long-running async work with waiting, failure, and canceling states
- app-wide blocs vs feature-owned blocs vs widget-owned blocs
- targeted rebuilds for performance-sensitive screens
- cross-bloc coordination without pushing orchestration into widgets
- a coherent ecosystem for storage, networking, auth, and routing

The framework is most compelling when you lean into ownership and lifecycle, not when you use it as a generic counter-style state wrapper.

## Core Capabilities

- **Use-case driven business logic**: blocs route events into dedicated use cases
- **Per-event concurrency**: `EventConcurrency.sequential`/`droppable`/`concurrent` on a `UseCaseBuilder` controls how same-type events interleave (1.5.0)
- **Lifecycle ownership**: `permanent`, `feature`, and `leased` lifecycles via `BlocScope`
- **Targeted rebuilds**: rebuild groups let widgets subscribe narrowly
- **Status-aware streams**: `StreamStatus` separates transient workflow state from persistent app state
- **Cross-bloc orchestration**: event subscriptions, state relays, and status relays

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

## Recommended Evaluation Path

Start with the examples that show Juice at its strongest:

1. `notes_app` in `packages/juice_examples`: leased editor, autosave, rebuild groups, storage
2. `social_feed`: fetch/caching/coalescing through `juice_network`
3. `dashboard`: auth lifecycle + routing guards
4. `ecommerce`: ecosystem composition across packages

The repository root `example/` app is a framework showcase and API sampler. It is useful for browsing concepts quickly, but it is not the primary architecture reference.

## Ecosystem Packages

- `juice_storage`: local persistence, TTL cache, secure storage
- `juice_network`: fetch, retry, coalescing, interceptor pipeline
- `juice_routing`: declarative routing and guard pipeline
- `juice_auth`: provider-agnostic session lifecycle

## Release Notes

This release tightens package hygiene, treats `packages/juice` as the single source of truth for the core framework, and shifts the public story toward lifecycle-aware app architecture rather than generic state management alone.
