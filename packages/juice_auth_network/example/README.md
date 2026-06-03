# juice_auth_network example

A single-screen demo that wires an `AuthBloc` into a `FetchBloc` using the three
`juice_auth_network` adapters.

Built with **Juice primitives only** — `AuthBloc`, `FetchBloc`, a `ProfileBloc`
feature bloc, and `StatelessJuiceWidget`. Every interaction is a bloc event; no
direct transport access, no `ValueNotifier`, no `setState`. State lives in
blocs; the UI rebuilds through rebuild groups.

## What it shows

1. **Log in** → `AuthBloc` authenticates via a self-contained `DemoAuthProvider`.
2. **Fetch /users/1** → `ProfileBloc` sends a request through `FetchBloc`;
   `AuthBlocAuthInterceptor` (registered via `InitializeFetchEvent`) injects the
   current access token. The panel shows the injected token and the response.
3. **Force refresh** → rotates the access token via `AuthBloc`'s singleflight
   refresh (`RefreshTokenEvent`); the next request carries the new token.

> **Automatic 401 → refresh → retry** (`AuthBlocRefreshInterceptor`) replays the
> failed request at the Dio transport layer, so it needs a shared `Dio`. That
> wiring is shown in the package [README](../README.md) and covered by the
> package tests; this example stays purely event-driven and drives refresh
> explicitly instead.

> Requires internet to fetch from `https://dummyjson.com` (same public API the
> juice_network example uses).

## Structure

- `lib/demo_wiring.dart` — `buildDemo()` wires the blocs. The refresh
  interceptor reuses `fetchBloc.dio`, so the example never references the
  transport package directly.
- `lib/profile_bloc.dart` — a `JuiceBloc<ProfileState>` feature bloc; the fetch
  result lands in its state via the use case, and the UI rebuilds through the
  `profile:data` group.
- `lib/home_screen.dart` — `StatelessJuiceWidget`s bound to `AuthBloc` and
  `ProfileBloc`.

## Run

```bash
flutter run
```
