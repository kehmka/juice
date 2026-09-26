# juice_lint

Analyzer rules for the [Juice](https://pub.dev/packages/juice) framework —
the `AGENTS.md` idioms enforced statically, so mistakes surface in the IDE
and in `dart analyze` instead of at runtime.

Built on Dart's official analyzer plugin API
([`analysis_server_plugin`](https://pub.dev/packages/analysis_server_plugin)),
so its diagnostics are reported by the stock `dart analyze` CLI and in CI —
not only in an IDE. Requires a Dart 3.10+ / Flutter 3.38+ SDK at analysis
time.

> **`flutter analyze` caveat (verified on Flutter 3.47.5):** `flutter
> analyze` drives the analysis server over LSP and exits as soon as the
> server reports analysis done — before the plugin isolate has published
> its results — so it prints "No issues found!" even when juice_lint has
> findings. Use `dart analyze` (it works on Flutter packages too) for the
> CLI/CI gate.

## Rules

Every rule is scoped to Juice's own types (`package:juice`), so a
same-named class from another package is never touched. All are warnings;
all but one are **enabled by default**.

| Rule | Default | Flags | Why |
| --- | --- | --- | --- |
| `juice_generic_event` | on | a concrete generic `EventBase` subclass (`Foo<T>`); abstract/sealed generic bases are exempt | events match by EXACT runtime type, so `typeOfEvent: Foo` never fires for `Foo<T>` — a silent dead event (gotcha 2) |
| `juice_mutable_state_field` | on | a non-`final` instance field on a `BlocState` | state is an immutable value changed only through `copyWith`. **Quick fix:** make it `final` |
| `juice_behavior_in_state` | on | a function/`Timer`/`StreamSubscription`/`StreamController`/`*Controller`/`*Bloc` field on a `BlocState` | state holds DATA, not behavior (gotcha 5) |
| `juice_send_in_build` | on | `bloc.send(...)` / `sendCancellable(...)` directly in a `build`/`onBuild` body | dispatches on every rebuild. Calls inside a closure (`onPressed:`, `builder:`) are not flagged |
| `juice_lease_in_build` | on | `BlocScope.lease(...)` / `leaseAsync(...)` directly in a `build`/`onBuild` body | a new, never-released lease per rebuild — lease in `initState`, release in `dispose` |
| `juice_stale_read_across_await` | on | a `bloc.state` snapshot, taken before an `await`, used in an emit's `newState:` after it | the #1 latent bug: it clobbers what another event emitted during the await (§4) |
| `juice_missing_concurrency_mode` | **opt-in** | `UseCaseBuilder(...)` / `UseCaseBuilder.typed(...)` with no `concurrency:` | the default is `concurrent`; a policy that every builder states its mode (§4). Opt-in because the default is legitimate for independent events |

A "build method" is a method named `build` or `onBuild` whose first
parameter is a Flutter `BuildContext`.

Considered and not shipped: a `copyWith` rule for `param ?? this.field` on
a nullable field (gotcha 6). Statically it cannot tell a field that must
be clearable (an error) from one that is set once and never cleared (a
`lastChangedAt`, a loaded profile) — and across the family 13 hits were
overwhelmingly the latter.

### `juice_stale_read_across_await` — the heuristic

Deliberately narrow; it reports only when ALL hold, in the `execute`
method of a `UseCase`/`BlocUseCase` subclass:

1. a local is initialized from a chain rooted at `bloc.state` —
   `bloc.state`, `bloc.state.items`, `bloc.state.items.where(…).toList()`,
   or a spread copy `[...bloc.state.items]` — with no `await` in it;
2. its type is the state itself or a collection (`Iterable`/`Map`).
   Scalars (an id used as a request key, a flag) are out of scope;
3. an `await` follows the declaration in the same function body;
4. after that `await`, the local is read inside the `newState:` argument
   of `emitUpdate`/`emitWaiting`/`emitFailure`/`emitCancel`;
5. the local is never reassigned (re-reading after the await is the fix).

Closures are skipped and order is textual. The rule can't see the event's
concurrency mode — and `sequential` only serializes events of the SAME
type, so another event can still emit during the await. When the stale
read is intended (a deliberate rollback), silence it at the use:

```dart
emitFailure(
  // ignore: juice_lint/juice_stale_read_across_await
  newState: previous,
  groupsToRebuild: {FooGroups.status},
);
```

## Use

No `pubspec.yaml` dependency is needed — the analysis server resolves the
plugin in its own synthetic package. Enable it in the package's (or
workspace root's) `analysis_options.yaml`, in a **top-level** `plugins:`
section (not the legacy `analyzer: plugins:` list):

```yaml
plugins:
  juice_lint: ^0.2.0          # once published; until then, a path or git source:
  # juice_lint:
  #   path: ../juice_lint     # relative to this analysis_options.yaml
```

Then `dart analyze` reports the rules (see the `flutter analyze` caveat
above). After changing
the `plugins:` section, restart the IDE's analysis server.

### Turning rules on and off

Project-wide, under the plugin's `diagnostics:`:

```yaml
plugins:
  juice_lint:
    path: ../juice_lint
    diagnostics:
      juice_missing_concurrency_mode: true   # opt in
      juice_send_in_build: false             # opt out
```

Per line / per file — note the `juice_lint/` prefix plugin diagnostics
use:

```dart
// ignore: juice_lint/juice_mutable_state_field
// ignore_for_file: juice_lint/juice_behavior_in_state
```

## Example

`example/README.md` walks each rule: the offending code, the exact
warning, and the fix, with the `AGENTS.md` idiom it encodes.

## Develop

The plugin entrypoint is `lib/main.dart` (the top-level `plugin`); rules
live in `lib/src/rules/`, the quick fix in `lib/src/fixes/`.

`example/` enables the plugin and plants one violation per
`// expect_lint: <rule>` marker (plus the correct forms, which must stay
clean). `dart run tool/check_fixtures.dart` (or `melos run lint:juice`
from the workspace root) runs `dart analyze` there and fails on any
missing, extra, or unrelated diagnostic. Because its warnings are the
point, `juice_lint_example` is excluded from `melos run analyze`.

Dogfood canary: the five `juice_examples` apps enable the plugin;
`melos run lint:juice` runs `dart analyze --fatal-infos` over them (plus
the fixture check), enforcing every default-on rule on real app code.
Planted-sentinel proof (2026-09-26, reverted): a non-final field on a
`BlocState` and a `bloc1.send(...)` in `NotesListScreen.onBuild` in
notes_app were reported by `dart analyze` as `juice_mutable_state_field`
and `juice_send_in_build`.
