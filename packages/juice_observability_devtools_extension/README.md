# juice_observability_devtools_extension

Source of the **Juice DevTools extension** — the companion extension shipped
inside [`juice_observability`](../juice_observability). Not published; the
BUILT web app is what ships.

It listens to the `juice:<type>` extension events `DevtoolsJuiceLogger`
posts and shows: a transitions **Timeline**, use-case duration **Spans**
(paired by `executionId` — honest even under `concurrent` overlap), a
per-**Bloc** view with the rebuild groups each emission targeted, and
**Problems** (errors, unhandled events, leak detection).

## Develop

```sh
flutter run -d chrome --dart-define=use_simulated_environment=true
```

## Ship (into the host package)

```sh
dart run devtools_extensions build_and_copy --source=. --dest=../juice_observability/extension/devtools
dart run devtools_extensions validate --package=../juice_observability
```

The build output lands in `../juice_observability/extension/devtools/build`
and is committed — pub.dev ships it with the package. Bump
`extension/devtools/config.yaml`'s `version` when the panel changes.
