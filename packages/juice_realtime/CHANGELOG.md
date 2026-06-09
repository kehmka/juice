# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
