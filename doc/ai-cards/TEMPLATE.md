# Juice AI Card — template & schema

An **AI card** is a dense, structured, per-package reference written *for AI
models* (coding agents, assistants). It lives at **`packages/<pkg>/doc/LLM.md`**
and lets an AI consume, implement-against, test, and debug a package without
reading its source. It complements — does not duplicate — the human `SPEC.md`
and `README.md`, and the framework-wide `AGENTS.md` (read that first for the
Juice mental model and gotchas).

This file defines the **card schema**. All cards conform to it so an AI can
pattern-match across the whole family.

## Card schema version: `1.0`

Bump the schema version (and this file) when the **structure** changes — a
section added/removed/reordered or a front-matter field changed. Cards declare
the schema they follow via front-matter so tooling and AI can adapt. Schema
changelog at the bottom.

## Front-matter (required)

Every card begins with a YAML front-matter block:

```yaml
---
card_schema: "1.0"          # the schema this card follows (this file's version)
package: juice_foo          # package name
version: 0.1.0              # the PACKAGE version this card documents (mirror pubspec)
requires:                   # min versions of juice-family deps
  juice: ">=1.5.0"
  juice_storage: ">=1.2.0"  # omit if none beyond juice
updated: 2026-06-09         # ISO date the card was last revised
---
```

- `version` mirrors the package's `pubspec.yaml` version. When the package bumps,
  review and bump the card. If they drift, the card is stale — fix it.
- `requires` mirrors the package's `pubspec.yaml` dependency constraints (e.g.
  `juice: ">=1.4.0"`). Bump `juice` to `">=1.5.0"` only once the package actually
  adopts `EventConcurrency`.

## Sections (in order)

Required unless marked *(optional)*. Keep each terse; prefer tables and
copy-paste snippets over prose. Omit an *(optional)* section by leaving it out
entirely (don't write "N/A").

| # | Section | Contents |
|---|---|---|
| 1 | `# juice_foo — AI card` + one-line | Title + a single sentence of what it is. |
| 2 | **Purpose / boundary** | 1–2 lines; **Owns:** … **Does NOT own:** … |
| 3 | **When to use** *(optional)* | When to reach for it vs. an alternative. |
| 4 | **Install** | `pubspec` deps + any platform setup (Info.plist, etc.). |
| 5 | **Construct** | `withConfig` snippet; required vs optional seams; note no-vendor default. |
| 6 | **Seams** | Each interface to implement, with its contract (what each thrown type/return means). |
| 7 | **API** | Public methods/getters with signatures. |
| 8 | **Events** *(optional)* | Table: event → effect; mark `internal` ones. Include if an AI would send/handle them directly. |
| 9 | **State** | Fields + derived getters. |
| 10 | **Rebuild groups** | Table: group → when emitted; note dynamic per-id groups. |
| 11 | **Concurrency** *(optional)* | Which events use which `EventConcurrency` mode / guard, and why. Include if non-`concurrent`. |
| 12 | **Recipes** | Copy-paste: consume; implement a vendor adapter for the seam; bind a widget; wire a sibling package. |
| 13 | **Testing** | How to fake the seam + drive the bloc + assert (the headless pattern + `settle()`). |
| 14 | **Failure modes** | What throws vs. emits failure; the fail-loud / retry contract; delivery guarantees. |
| 15 | **Anti-patterns** | Explicit "do NOT …" list of common misuse. |
| 16 | **Integrates with** *(optional)* | Sibling packages it pairs with (e.g. permissions via `PermissionBinding`). |
| 17 | **Invariants / gotchas** | Package-specific rules that aren't obvious. |
| 18 | **See also** | Links: `SPEC.md`, `README.md`, repo `AGENTS.md`. |

## Authoring rules

- **Don't repeat the framework primer.** For bloc/event/use-case/groups/
  StatelessJuiceWidget/seam basics and the universal gotchas, point to
  `AGENTS.md`. The card is package-specific.
- **Snippets must be runnable** (imports implied). Prefer the real adapter shape
  (e.g. a Dio executor) over pseudocode.
- **Tables for surfaces** (events, groups, state), prose only where judgment is
  needed (when-to-use, anti-patterns).
- **Be honest about scope** — list what's deferred/out-of-scope and link the
  ROADMAP for tracked items.
- Target length: ~120–200 lines. A trivial package may be shorter; never pad.

## Skeleton

```markdown
---
card_schema: "1.0"
package: juice_foo
version: 0.1.0
requires: { juice: ">=1.5.0" }
updated: 2026-06-09
---

# juice_foo — AI card

> One sentence. Read repo `AGENTS.md` for the Juice mental model + gotchas.

## Purpose
**Owns:** … **Does NOT own:** …

## Install
## Construct
## Seams
## API
## Events            <!-- optional -->
## State
## Rebuild groups
## Concurrency        <!-- optional -->
## Recipes
## Testing
## Failure modes
## Anti-patterns
## Integrates with    <!-- optional -->
## Invariants
## See also
```

## Schema changelog

- **1.0** (2026-06-09) — initial schema: front-matter + the 18-section layout.
