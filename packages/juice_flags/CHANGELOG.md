# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-05-28

### Added

- Initial release.
- **`FlagsBloc`** — feature flags / remote config with **per-flag selective
  rebuilds**: a widget bound to `FlagsGroups.flag('x')` rebuilds only when that
  flag's value changes. A fetch diffs old vs new and emits only the changed
  flags' groups.
- **`FlagsSource`** — vendor seam (`fetch()` + optional `changes()` stream), so
  Firebase Remote Config / LaunchDarkly / an endpoint / a local map are all just
  implementations. Default **`StaticFlagsSource`** (in-memory).
- **Layered resolution** — `defaults < fetched < overrides`; reads always
  resolve via typed accessors `boolFlag`/`stringFlag`/`intFlag`/`doubleFlag`/
  `json<T>`.
- **Fail-loud, read-safe fetch** — a failure surfaces in `state.error` (logged),
  while reads keep falling back to last-known/defaults.
- **Local overrides** — `setFlagOverride`/`clearFlagOverride` (dev toggles).
- **Live updates** — subscribes to `source.changes()` when provided.
- **Rebuild groups** — `flags:flag:<key>`, `flags:any`, `flags:status`.
