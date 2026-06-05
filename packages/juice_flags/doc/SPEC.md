# juice_flags Specification

> **Status:** Implemented (shipping).
> **Package:** `juice_flags`
> **Primary Bloc:** `FlagsBloc`

## Overview

Feature flags / remote config behind a `FlagsSource` seam, with **per-flag
selective rebuilds**. The bloc is vendor-free; Firebase Remote Config /
LaunchDarkly / an endpoint / a local map are all source implementations.

## Domain boundary

- **Owns:** the resolved value of each flag, plus fetch status.
- **Does NOT own:** *where* values come from (the source), nor the vendor SDK.
  A remote source is a provider impl behind the seam — **not** a glue package
  and **not** a vendor-shaped bloc.

## Seam

`FlagsSource`: `fetch()` (pull all values), `changes()` (optional live stream,
null if pull-only), `dispose()`. Values are vendor-agnostic: `bool` / `num` /
`String` / JSON-decodable. Default `StaticFlagsSource` (in-memory).

## Layered resolution

`resolve() = {...defaults, ...fetched, ...overrides}` — **defaults < fetched <
overrides**. `state.values` holds the resolved map. Typed accessors
(`boolFlag`/`stringFlag`/`intFlag`/`doubleFlag`/`json<T>`) read from it with a
fallback, so a flag always resolves.

## Selective refresh (diff-on-fetch)

| Group | Emitted when |
|---|---|
| `FlagsGroups.flag(key)` → `flags:flag:<key>` | that flag's resolved value changed |
| `FlagsGroups.any` → `flags:any` | any flag changed |
| `FlagsGroups.status` → `flags:status` | fetch lifecycle (loading/error) changed |

On every fetch / stream push / override change, the bloc computes
`changedKeys(old, new)` (added, removed, or changed) and emits only those flags'
groups (+ `any`). A refresh touching 2 of 50 flags rebuilds only 2 widgets.

## State

```dart
class FlagsState extends BlocState {
  final Map<String, Object?> values;  // resolved
  final bool loading;
  final String? error;                // surfaced; reads stay safe
  final bool fetched;
}
```

## Events

| Event | Effect |
|---|---|
| `InitializeFlagsEvent(config)` | seed defaults, subscribe to `changes()`, optional first fetch |
| `RefreshFlagsEvent` | pull from source, emit changed flags |
| `FlagsUpdatedEvent(values)` | internal — live-stream values arrived |
| `FlagsFetchFailedEvent(error)` | internal — live-stream error |
| `SetFlagOverrideEvent(key, value)` | local override (wins) |
| `ClearFlagOverrideEvent(key)` | revert override |

## Fail-loud, read-safe

A failed fetch → `emitFailure` with `state.error` (logged), `loading=false`,
resolved values **left intact**. Reads keep returning last-known/defaults — a
flag must always resolve. This is the one legitimate, *loud* fallback: error
visible, values safe.

## Testing

Headless with a fake source. Covered: defaults before fetch, fetched overlays
default, **diff-on-fetch** (only changed flag's group emitted), fetch failure
(error surfaced + reads safe), **live stream** updates only changed flags,
overrides win/clear, close disposes source. 8 tests.

## Spec Version

| Version | Date | Status |
|---|---|---|
| 1.0 | 2026-05-28 | Implemented |
