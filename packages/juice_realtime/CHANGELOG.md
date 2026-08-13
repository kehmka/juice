# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
