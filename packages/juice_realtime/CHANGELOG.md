# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.0] - 2026-10-14

### Changed

- **Requires `juice ^2.0.0`.** A connection's message stream is a bloc-owned
  binding (`bindStream(..., key: 'messages')`): cancelled before the use cases
  close, replaced by the next connection's. A socket error ends the binding and
  is handled as a connection loss (the reconnect policy applies), where before
  the subscription outlived the error until the loss handling cancelled it.
- `close()` marks the manual close, closes the bloc (its message binding is
  cancelled), closes the socket and the broadcast stream, then disposes the
  connector; a failed binding cancel, socket close or dispose is logged and the
  rest of the teardown still runs; an uninitialised bloc closes cleanly; a
  second `close()` awaits the first.
- `config` before `InitializeRealtimeEvent` throws a named `StateError` instead
  of a late-initialisation error.
- A second `InitializeRealtimeEvent` after the first completed is refused with a
  `StateError` through the use case's error path (logged as `use_case_error` and
  `bloc_error`); the bloc owns one connector for its life, and the first stays
  live. Before, the config was silently replaced and the first connector never
  disposed.
- A connection attempt that fails after it was superseded (a disconnect, a
  reconnect or close overtook it) is logged as a bloc error; before, the failure
  was dropped.

## [0.2.0] - 2026-08-12

### Changed

- Require `juice ^1.6.0` and declare a concurrency mode for every event.
- Use `droppable` for initialization, connect/reconnect/disconnect, and
  connection-loss handling; keep the shared `_connecting` guard because connect
  and reconnect are different event types.
- Run outbound sends, connection-established updates, and inbound message
  updates `sequential`ly to preserve ordering and state mutation safety.

### Fixed

- Reject stale connector completions and callbacks with a connection epoch, so
  disconnecting during a pending connect cannot be undone by its late result.
- Cancel a scheduled reconnect when a user initiates a fresh connect.
- Detach connection resources before awaiting their cleanup, making overlapping
  lifecycle teardown safe and idempotent.

### Tests

- Add gated coverage for connect/reconnect exclusion, disconnect versus a late
  connect completion, manual-connect timer supersession, and outbound FIFO
  ordering; burst messages verify ordered delivery and counting.

## [0.1.1] - 2026-05-28

### Fixed

- Overlapping connects now open only one connection (added a `_connecting`
  guard to `ConnectEvent`/`ReconnectEvent`) — a connect fired during an
  in-flight connect previously tore down and re-opened, risking a dangling
  subscription.

## [0.1.0] - 2026-05-28

### Added

- Initial release.
- **`RealtimeBloc`** — a persistent realtime connection with connection status
  as state and **automatic reconnection (exponential backoff)**.
- **`RealtimeConnector` / `RealtimeConnection`** — vendor seam (one connect
  attempt = one connection). Default **`WebSocketRealtimeConnector`**
  (`web_socket_channel`; mobile/desktop/web). SSE or a vendor SDK can implement
  the same seam.
- **Message delivery** — `bloc.messages` broadcast stream (every message, for
  consumers like chat) plus `state.lastMessage` + the `realtime:message` group
  (latest, for simple widgets).
- **Reconnection** — configurable `initialBackoff` / `maxBackoff` /
  `maxReconnectAttempts`; gives up loudly when exhausted. Manual `disconnect()`
  suppresses reconnection.
- **Fail-loud send** — `send()` while not connected surfaces an error (never a
  silent drop).
- **Rebuild groups** — `realtime:status`, `realtime:message`.

### Not yet included

- SSE / topic multiplexing — both fit behind the existing seam; planned post-0.1.
