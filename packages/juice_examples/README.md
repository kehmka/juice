# juice_examples

Production-quality example apps showcasing the [Juice](https://pub.dev/packages/juice) state management ecosystem.

Start here if you want to evaluate Juice for real application architecture. These examples are the primary public onboarding path. The repository-root `example/` app is a showcase/sandbox for individual framework concepts.

## Examples

| # | App | Packages | What It Demonstrates |
|---|-----|----------|---------------------|
| 1 | **Notes** | juice, juice_storage | Offline-first persistence, rebuild groups, leased editor bloc, auto-save |
| 2 | **Social Feed** | juice, juice_network | FetchBloc, CachePolicy, pagination, pull-to-refresh |
| 3 | **Dashboard** | juice, juice_routing, juice_auth | AuthProvider, route guards (Auth/Role/Guest), RBAC |
| 4 | **E-Commerce** | juice, juice_network, juice_storage, juice_routing | All packages working together, cross-bloc communication |
| 5 | **Chat** | juice, juice_storage | Multi-bloc coordination, simulated real-time streams |

## Recommended First Pass

If you are evaluating whether Juice is worth adopting, use this order:

1. **Notes**: best demonstration of lifecycle ownership, storage integration, targeted rebuilds, and stateful use cases
2. **Social Feed**: best demonstration of `juice_network`
3. **Dashboard**: best demonstration of auth + routing working together
4. **E-Commerce**: best demonstration of package composition
5. **Chat**: useful for multi-bloc coordination patterns

## Running an Example

Each example is a standalone Flutter app:

```bash
cd packages/juice_examples/example/notes_app
flutter run
```

## Package Structure

```
packages/juice_examples/example/
├── notes_app/          # 1. Offline-First Notes
├── chat_app/           # 2. Real-Time Chat
├── social_feed/        # 3. Social Feed (Instagram-style)
├── dashboard/          # 4. Admin Dashboard with RBAC
└── ecommerce/          # 5. E-Commerce Product Browser
```

## Key Patterns

### Bloc + State + Events + Use Cases
Every example follows the Juice pattern: immutable state with `copyWith`, typed events, and use cases that encapsulate business logic.

### Rebuild Groups
Selective widget rebuilds via named groups — only the widgets observing a specific group rebuild when that group's data changes.

### StatelessJuiceWidget
Single-bloc widgets that automatically lease and dispose blocs, with built-in group filtering.

### JuiceBuilder2
Multi-bloc observation for screens that need data from two blocs simultaneously.

### FetchBloc + CachePolicy
Network requests with automatic caching, retry, and request coalescing via juice_network.

### Route Guards
Declarative navigation protection with AuthGuard, RoleGuard, and GuestGuard from juice_routing.

### AuthProvider
Provider-agnostic authentication lifecycle with token refresh and session persistence via juice_auth.
