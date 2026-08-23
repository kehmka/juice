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

Don't publish `juice_observability` by hand — the built bundle is **not in
git** (44 MB of Flutter-web + CanvasKit; `extension/devtools/build/` is
git-ignored). A `.pubignore` re-includes it in the pub archive, and the
publish script rebuilds it first so the shipped bundle is never stale:

```sh
bash packages/juice_observability/tool/publish.sh   # from the repo root
```

That runs `build_and_copy` → `validate` → `flutter pub publish`. For a
quick local rebuild without publishing:

```sh
dart run devtools_extensions build_and_copy --source=. --dest=../juice_observability/extension/devtools
```

Bump `extension/devtools/config.yaml`'s `version` when the panel changes.
