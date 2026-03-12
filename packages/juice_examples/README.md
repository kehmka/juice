# juice_examples

Production-quality example apps showcasing the [Juice](https://pub.dev/packages/juice) state management ecosystem.

## Examples

| # | App | Packages | What It Demonstrates |
|---|-----|----------|---------------------|
| 1 | **Notes** | juice, juice_storage | Offline-first persistence, rebuild groups, auto-save |
| 2 | **Chat** | juice, juice_storage | Multi-bloc (JuiceBuilder2), simulated real-time streams |
| 3 | **Social Feed** | juice, juice_network | FetchBloc, CachePolicy, pagination, pull-to-refresh |
| 4 | **Dashboard** | juice, juice_routing, juice_auth | AuthProvider, route guards (Auth/Role/Guest), RBAC |
| 5 | **E-Commerce** | juice, juice_network, juice_storage, juice_routing | All packages working together, cross-bloc communication |

## Running an Example

Each example is a standalone Flutter app:

```bash
cd example/notes_app
flutter run
```

## Package Structure

```
example/
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
