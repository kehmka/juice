# Developer experience vs Juice

## 1. Landscape snapshot (versions/URLs read; the macros status finding stated plainly)

Read 2026-09-16. Juice baseline: `/Users/kevinehmka/dev/juice` at `f301781` (juice 1.7.2, juice_lint 0.1.0 `publish_to: none`, juice_observability 0.5.0 + DevTools extension, skill bundle 0.1.0). Local SDK: Dart 3.12.2 / Flutter 3.44.4.

- **Dart macros are cancelled.** dart.dev/language/macros: work stopped 29 Jan 2025 ("too far away from shipping macros with the developer-time performance we require"). Replacements: language-level data support (primary constructors stable "as of Dart 3.13" per the freezed README), **augmentations** ("stands on its own and will improve existing code generation"), and build_runner performance work. Codegen packages remain the norm: freezed 4.0.1, riverpod_generator 4.0.9 ("entirely optional").
- **custom_lint 0.8.1 is "no longer under active development"** (README, raw fetch); it recommends the official `analysis_server_plugin` 0.3.23 (tools.dart.dev, Dart ≥3.10), enabled via a top-level `plugins:` key in `analysis_options.yaml`, whose diagnostics **are reported by `dart analyze`/`flutter analyze`** (dart.dev/tools/analyzer-plugins). juice_lint is built on the abandoned host. riverpod_lint 3.1.9: 15 rules, 6 assists. bloc_lint 0.4.2: standalone linter on `_fe_analyzer_shared` (pubspec), run as `bloc lint .`.
- DevTools: riverpod_devtools (graph, inspector, event log, MCP), signals_devtools_extension ("early"), Patrol (native UI tree for selectors), bloc_devtools_extension 0.2.0 (third-party, time travel + diff).
- Testing: bloc_test 10.0.0; riverpod 3.4.3 `ProviderContainer.test()`; `testWidgets` runs inside `FakeAsync` (api.flutter.dev); alchemist 0.14.0. Scaffolding: very_good_cli 1.5.0, mason, stacked_cli.
- Migration: `lib/fix_data.yaml` (flutter/flutter Data-driven-Fixes.md); `pub upgrade --major-versions` / `--tighten`.
- Docs: docs.page (Invertase, free OSS, auto-llms.txt + MCP). DartPad: only gist iframes remain and only 36 whitelisted packages (bloc, riverpod, provider in; **juice not importable**).
- AI: llmstxt.org; agents.md (Linux Foundation, 60k+ repos); **dart.dev/tools/pub/package-skills** — `skills/<package>-<name>/SKILL.md` inside the pub package, bundled by `dart pub publish`, installed by `dart run skills@ get` (`skills` 1.0.1, labs.dart.dev) into Claude Code/Cursor/Codex/Copilot/…; official `flutter/agent-plugins` (Claude plugin `dart-flutter`, 10 skills, rules, Dart MCP server).

## 2. Mechanism catalog — for EACH mechanism:

### build_runner code generation (freezed / json_serializable / riverpod_generator)
- **What it does / problem solved**: generates `copyWith`, `==`/`hashCode`, `toString`, unions, JSON and (riverpod) provider declarations from annotations.
- **How it works (the sophisticated part)**: `build_runner` runs each `Builder` over annotated inputs through `source_gen`'s resolved element model (types, not text), writing `part` files the source must declare; `watch` is incremental via an asset graph. freezed's copyWith solves nullable-clear with an internal sentinel — the `_unset` problem Juice documents by hand. riverpod_generator derives the provider kind from the return type. The cost is a second artifact that must be regenerated and kept in sync.
- **Juice today** — `lacks` (by decision). No build_runner/freezed/json_serializable in any `packages/*/pubspec.yaml`; AGENTS.md §2 hand-writes `copyWith` + `_unset`; `juice_mutable_state_field` enforces `final`.
- **Gap value** — Med for app authors with many states (gotcha 6 is error-prone); Low for the framework.
- **Adoption sketch** — Build nothing. A one-paragraph "using freezed for a BlocState" note in AGENTS.md is S, after a spike confirming `@freezed class X extends BlocState` works (unverified).
- **Doctrine fit** — "code is the source of truth" forbids a Juice-owned generator; letting apps opt in costs nothing.

### Lint packages with quick-fixes (custom_lint → analysis_server_plugin; riverpod_lint; bloc_lint)
- **What it does / problem solved**: framework idioms as IDE squiggles with one-click fixes.
- **How it works (the sophisticated part)**: under custom_lint a `DartLintRule.run` registers AST visitors on `context.registry` and reports with `reporter.atNode`; a fix is a `DartFix.run(resolver, reporter, context, analysisError, others)` that calls `reporter.createChangeBuilder(message:, priority:)` then `addDartFileEdit` to insert/replace source; a `DartAssist` attaches to a `SourceRange` instead (riverpod_lint's "wrap with Consumer"). The analysis server runs the plugin in an isolate so IDEs show it, but `flutter analyze` never reports it. The official `analysis_server_plugin` fixes this: `Plugin.register` with rules, `registerFixForRule`, assists, declared under `plugins:`, surfaced by `dart analyze`. bloc_lint went a third way — its own parser-level linter plus a CLI.
- **Juice today** — `partial (no quick-fixes; abandoned host)`. `packages/juice_lint/lib/src/*.dart`: three rules, no `getFixes`/`DartFix`/`Assist` (grepped); the rule file's own comment says it is stuck on deprecated APIs "until custom_lint adopts the diagnostic API" — it never will. Dogfooded on five example apps via `melos run lint:juice`; `expect_lint` fixtures in `example/lib/fixtures.dart`.
- **Gap value** — High for consumers and for Juice's CI (rules would run under `flutter analyze`).
- **Adoption sketch** — Port to `analysis_server_plugin`: M (three rules on the official API + one fix: insert `final`). Maintenance drops — one official API instead of custom_lint's analyzer pins. Local SDK 3.12 ≥ 3.10.
- **Doctrine fit** — Fail loud at edit time; rules derive from AGENTS.md, not a second truth. A fix must emit exactly the §2 shape.

### DevTools extensions
- **What it does / problem solved**: a framework tab showing live state, transitions, dependencies, problems.
- **How it works (the sophisticated part)**: the app posts `dart:developer` `postEvent` on the extension stream (or registers service extensions); the extension — a Flutter web app declared in `extension/devtools/config.yaml`, built into `extension/devtools/build/` — is discovered from the pub dependency, enabled once, and reads `serviceManager.service.onExtensionEvent` or pulls on demand via `callServiceExtensionOnMainIsolate` / `EvalOnDartLibrary`. The stream has no replay. The best panels add time-travel with diffs (bloc_devtools_extension), dependency graphs (riverpod, signals), and an MCP bridge (riverpod_devtools).
- **Juice today** — `has`. `devtools_juice_logger.dart` posts `juice:<type>` via `developer.postEvent`; `telemetry_store.dart` listens on `onExtensionEvent`; four views (Timeline, Spans, Blocs, Problems), live-verified in DevTools 2.57.0. Missing vs the best: state **diff**, a rebuild-group → widget view, any pull path (`registerExtension`: none).
- **Gap value** — Med. Diff and "which widgets rebuilt for this group" would beat the field because groups are named intents.
- **Adoption sketch** — Diff view S–M (store already keeps the last summary). Group-rebuild view M — new core instrumentation (`widget_rebuilt{groups}` from `StatelessJuiceWidget`). Replay L and off-doctrine. Maintenance: a web app rebuilt per publish; config.yaml version drift already happened once.
- **Doctrine fit** — Observability of the existing seam; skip time-travel.

### Bloc test harness (blocTest / ProviderContainer.test / BlocTester)
- **What it does / problem solved**: seed, act, assert the exact emitted sequence, repeatably.
- **How it works (the sophisticated part)**: `blocTest(build:, seed:, act:, wait:, skip:, expect:, errors:, verify:)` builds the bloc in-test, seeds via `emit`, subscribes, runs `act`, waits, then **closes the bloc before evaluating** so no late emission leaks; `MockBloc` + `whenListen` stub a stream and keep `state` in sync for widget tests. `ProviderContainer.test()` isolates a container per test, disposes via `addTearDown`, and adds an end-of-test check that every container was disposed; `container.listen` records transitions.
- **Juice today** — `has-under-another-name`, `partial (not declarative, no close-before-assert, no leak check, unused)`. `packages/juice/lib/src/testing/bloc_tester.dart`: `BlocTester` records emissions, `send()` sleeps a fixed 10 ms, `expectStatusSequence`, `waitForEmissions`, `dispose()`. Used only by `example/test/features_showcase_test.dart`; every package test uses the raw fake-the-seam + `settle()` pattern (AGENTS.md §6).
- **Gap value** — Med–High; the 10 ms sleep is the flake blocTest was built to remove.
- **Adoption sketch** — `juiceTest(build:, seed:, act:, expect:, groups:)` in `testing.dart`, asserting on `groupsToRebuild` (Juice's differentiator), closing before assert, with a `BlocScope.enableLeakDetection` check: S–M, one file.
- **Doctrine fit** — "Demonstrate in full": adopt it in the package tests or don't ship it.

### Mocking, fake time, goldens (mocktail / FakeAsync / alchemist)
- **What it does / problem solved**: deterministic collaborators, clocks and pixels.
- **How it works (the sophisticated part)**: mocktail stubs without codegen via `when(() => …)` closures; `FakeAsync` swaps the zone's timer/microtask factories so `elapse()`/`flushTimers()` fire scheduled work synchronously — `testWidgets` already runs inside one, `pump(Duration)` advances it, `runAsync` escapes; alchemist wraps goldens with text-obscured "CI goldens" to dodge font drift.
- **Juice today** — `partial`. mocktail is a dev dep in five packages (storage, network, auth, auth_network, auth_routing); doctrine prefers hand-written seam fakes. No `FakeAsync` in any test and no `matchesGoldenFile` (grepped).
- **Gap value** — Med for the timer-bearing packages (sync outbox, network retry, realtime reconnect); Low for goldens.
- **Adoption sketch** — `package:fake_async` in those tests: S per package, no new API. Goldens: not for Juice.
- **Doctrine fit** — Fakes over mocks is already doctrine; fake time is rigor.

### Scaffolding CLIs and templates (very_good_cli / mason / stacked)
- **What it does / problem solved**: one command creates a package/feature in the house shape.
- **How it works (the sophisticated part)**: a mason brick is `brick.yaml` (typed `vars` with prompts/defaults) plus a `__brick__/` tree whose file names and contents are mustache templates with case lambdas (`{{name.snakeCase()}}`), partials, and Dart `pre_gen`/`post_gen` hooks; distributed via BrickHub/git/path. very_good_cli layers opinionated bricks and `very_good test --min-coverage`; stacked_cli edits `app.dart` in place.
- **Juice today** — `lacks`. No `brick.yaml`/`mason.yaml`; the canonical shape exists as AGENTS.md §2 prose plus 24 real packages.
- **Gap value** — Med for humans starting a `juice_foo`; Low for agents (the skill emits the shape).
- **Adoption sketch** — One `juice_package` brick under `tool/bricks/`: S to write, but it is a second copy of §2. Only acceptable if its output is a checked-in fixture package that CI analyzes and tests, so the brick is proven not documented. Every core API change then touches both.
- **Doctrine fit** — Borderline; gated as above or not at all.

### Docs sites and interactive examples (docs.page / DartPad / Jekyll)
- **What it does / problem solved**: browsable, searchable docs with runnable snippets.
- **How it works (the sophisticated part)**: docs.page renders MDX from a repo path with branch/PR previews, search, and per-site `llms.txt` + MCP. DartPad embeds are now gist-only iframes (`dartpad.dev/?id=<gist>&theme=…`) restricted to 36 whitelisted packages — a Juice snippet cannot run there.
- **Juice today** — `has` (Jekyll/just-the-docs via `.github/workflows/jekyll-gh-pages.yml`; `doc/` dated Jan 2025–Jun 2026; `doc/api/` dartdoc). Risk: `doc/testing/bloc-tester.md` documents a class no package uses; the human site has no drift check, unlike the cards.
- **Gap value** — Low–Med; the cards + AGENTS.md are the real docs now.
- **Adoption sketch** — A `tool/check_docs.sh` grepping `doc/` for symbols absent from `lib/`: S. DartPad: impossible.
- **Doctrine fit** — Fine as-is; docs.page would be a second doc system plus a hosted dependency.

### Migration tooling (`fix_data.yaml` / `pub upgrade --major-versions`)
- **What it does / problem solved**: consumers cross a breaking change with `dart fix --apply`.
- **How it works (the sophisticated part)**: a package ships `lib/fix_data.yaml` — `version: 1`, `transforms:` each with `title`, `date`, an `element` selector (`uris` + `class/method/field/inClass`) and `changes` of kind `rename`, `addParameter`, `removeParameter`, `renameParameter`, `changeParameterType`, `replacedBy`, with optional `oneOf` and `bulkApply`; the analyzer matches usages in the consumer's code and rewrites them; the package tests it with `test_fixes/<f>.dart` + `.dart.expect` under `dart fix --compare-to-golden`. `pub upgrade --major-versions` rewrites constraints to what `pub outdated` reports resolvable; `--tighten` raises lower bounds to the resolved versions.
- **Juice today** — `lacks`. No `fix_data.yaml` (find'd). Core carries `@Deprecated` on `RelayUseCaseBuilder` ("Use StateRelay or StatusRelay… removed in v2.0.0") and two in `bloc_event.dart` — exactly the `replacedBy` shape. Migrations are CHANGELOG prose.
- **Gap value** — Med now, High the day v2.0.0 lands.
- **Adoption sketch** — One `fix_data.yaml` + `test_fixes/` pair in `packages/juice`: S; append per breaking rename; goldens catch rot. `--tighten` mechanizes docket §7's "no floor is dishonest".
- **Doctrine fit** — Declarative, tested, no generated code.

### Error UX (error boundaries, redbox, structured reporting)
- **What it does / problem solved**: a build-time throw becomes a readable, copyable panel; runtime failures carry context.
- **How it works (the sophisticated part)**: `ErrorWidget.builder` is Flutter's global hook; frameworks wrap `build` in try/catch and render a boundary; observability layers chain `FlutterError.onError` / `PlatformDispatcher.onError`, attach breadcrumbs, fan out to reporters.
- **Juice today** — `has`. `JuiceWidgetSupport.processWithErrorHandling` and three `JuiceBuilder` sites render `JuiceExceptionWidget` (copy-to-clipboard, selectable trace, dismiss). `juice_observability` installs both global handlers, chains and restores prior ones, keeps a 50-entry breadcrumb ring, isolates reporter failures; use-case failures reach the DevTools Problems view. Verified gap: no `kReleaseMode`/`kDebugMode` anywhere under `packages/juice/lib/src/ui` — a release user can see a stack trace.
- **Gap value** — Low, but the release exposure is real.
- **Adoption sketch** — Release-mode fallback tile behind the existing widget: S. It is a default, so it needs Kevin's ruling.
- **Doctrine fit** — Loud in debug and to the reporter; what the release user sees is a doctrine call.

### Hot-reload friendliness (state preservation across reload)
- **What it does / problem solved**: edit-and-see without losing app state.
- **How it works (the sophisticated part)**: hot reload swaps method bodies on the live heap; long-lived objects survive, constructor work does not re-run. Riverpod additionally re-executes only the provider whose source changed (riverpod_generator docs). Bloc instances live as long as their owning widget.
- **Juice today** — `has` with one undocumented nuance. `BlocScope._entries` is a `static final Map`, so registered blocs and state survive; `execute()` edits apply on the next event. But `JuiceBloc._registerUseCases` materializes the builder list once at construction (`juice_bloc.dart:290-292`) and there is no `reassemble` hook (grepped), so **adding a `UseCaseBuilder` to a live bloc needs a hot restart** — the same "my event does nothing" symptom as the generic-event gotcha.
- **Gap value** — Low–Med; one sentence saves a confused session.
- **Adoption sketch** — Add to AGENTS.md gotchas: S. Re-registering on `reassemble` is a new dev-only code path — skip.
- **Doctrine fit** — Documentation only.

### AI-agent affordances (llms.txt / AGENTS.md / package skills / Claude plugin)
- **What it does / problem solved**: a framework absent from training data still gets written correctly.
- **How it works (the sophisticated part)**: llms.txt is H1 + blockquote + H2 link lists; AGENTS.md is a "README for agents", nearest-file-wins, read by Codex/Cursor/Copilot/Jules/Gemini CLI; the Dart-official channel is **package skills** — `skills/<package>-<name>/SKILL.md` inside the pub package, bundled by `dart pub publish`, discovered from the consumer's dependency tree by `dart run skills@ get` and installed into every major agent's skills directory. The official Flutter Claude plugin adds rules, skills and the Dart MCP server.
- **Juice today** — `has` (ahead of most), `partial` on the pub channel. Verified: root `AGENTS.md`, spec-conformant `llms.txt`, 24 versioned cards, `check_cards.sh`, `sync_skill.sh --check`, Claude plugin (`.claude-plugin/`, `skills/juice/SKILL.md`). Gap: the skill sits at the monorepo root, not in `packages/juice/skills/`, and is named `juice` — the spec requires `juice-<name>` and the installer "skips non-conforming skills". `dart run skills@ get` in a consumer finds nothing; only Claude-marketplace users get it. No Cursor/Codex rule files.
- **Gap value** — High: the pub channel is agent-agnostic, zero-install, and the one dart.dev documents.
- **Adoption sketch** — Emit the bundle to `packages/juice/skills/juice-framework/` from `sync_skill.sh`; point `.claude-plugin` at it: S–M; maintenance unchanged.
- **Doctrine fit** — Exact: doctrine stays in AGENTS.md/cards; skills remain drift-checked copies.

## 3. Not worth adopting (one line each with the reason)

- A `juice_generator` / freezed-style codegen for `BlocState`: generated code is a second truth plus a build_runner dependency; the lint already enforces the shape.
- DevTools time-travel / replay: re-emitting state outside a use case breaks event-in/state-out.
- DartPad embeds: Juice is not on the 36-package whitelist.
- docs.page: a hosted second doc system; the cards are already the AI surface.
- A very_good_cli-style umbrella CLI: a whole tool for one template.
- bloc_lint's standalone-linter approach: reimplementing analysis on `_fe_analyzer_shared` is a maintenance sink now that the official plugin API reports from the CLI.
- `MockBloc`/`whenListen` mock blocs: a real bloc with a fake seam is the cheaper, truer double.
- Golden tests: Juice ships no visual components.

## 4. Top 5 recommendations, ranked, one paragraph each, with the gate that should precede building

1. **Port `juice_lint` to `analysis_server_plugin`, add its first quick-fix.** custom_lint is abandoned by its own README, the rule file already admits it is stuck on deprecated APIs, and the official host reports diagnostics from `flutter analyze` — so `melos run analyze` and CI would enforce the rules instead of a side script. Add one fix (`juice_mutable_state_field` → insert `final`) to prove the fix path. Gate: confirm consumers (Amoli) are on Dart ≥3.10, and re-run the docket §5 planted-sentinel test under the new host before deleting the custom_lint version.

2. **Ship the skill through the pub package-skills channel.** Have `sync_skill.sh` emit `packages/juice/skills/juice-framework/` so `dart run skills@ get` installs it into Claude Code, Cursor, Codex, Copilot and the rest from the dependency tree, with the sync script still the only writer. Gate: prove on a scratch consumer that the `skills` CLI accepts the name and that `dart pub publish --dry-run` bundles the directory cleanly.

3. **Add `lib/fix_data.yaml` for the existing deprecations.** Three `@Deprecated` members already promise v2.0.0 removal; encode them as `replacedBy`/`rename` transforms with a `test_fixes/` golden so `dart fix --apply` carries consumers over. Gate: Kevin confirms the v2 removal list is final.

4. **A declarative `juiceTest`, adopted by the packages.** `BlocTester` is unused and sleeps 10 ms; a `blocTest`-shaped helper that closes before asserting, asserts on `groupsToRebuild`, and runs a `BlocScope` leak check would be the harness the family actually uses. Gate: migrate juice_theme and juice_sync (both just touched); keep it only if it removes `settle()` calls rather than adding a layer.

5. **DevTools state diff + group-rebuild view; document the hot-reload nuance.** A diff of consecutive Blocs summaries is small; a `widget_rebuilt{groups}` event from `StatelessJuiceWidget` would make Juice the only framework whose DevTools explains *why* a widget rebuilt, by name. Gate: it is new core instrumentation — approve the event schema, confirm it is a no-op without `DevtoolsJuiceLogger`, measure overhead on notes_app. The AGENTS.md sentence ("new builders need a hot restart") needs no gate.

## 5. Things Juice already does BETTER on DX than most of the ecosystem (be specific)

- **A drift-checked AI documentation system**: 24 per-package cards on a versioned schema, `check_cards.sh` failing on version/`requires` drift, `sync_skill.sh --check` failing when skill copies diverge. Neither bloc nor riverpod ships per-package AI cards; docs.page *generates* an llms.txt, Juice *curates* one.
- **Gotchas-as-lints with a proof fixture**: each rule cites the AGENTS.md section it encodes, and `fixtures.dart` is a self-verifying `expect_lint` suite; riverpod_lint has more rules but no doctrine trace per rule.
- **A DevTools extension that is a decorator on an existing seam**: `DevtoolsJuiceLogger(inner:)` wraps the logger; the `executionId`-paired spans with `elapsedMicros` were already logged. bloc has no official extension; riverpod's needs an observer plus a CLI static-analysis step.
- **The canonical package shape is real, 24 times**: every `juice_*` is the same skeleton, so agents copy a demonstrated package rather than a generated one.
- **A shipped error boundary**: `JuiceExceptionWidget` with copy-to-clipboard wired into all three builder paths; most state libraries leave `ErrorWidget.builder` to the app.
- **Publish hygiene that has caught real drift**: `cards:check` "caught four real drifts" on its first run; `pana` checks none of this.
