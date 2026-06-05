# juice_realtime Specification

> **Status:** Implemented (shipping).
> **Package:** `juice_realtime`
> **Primary Bloc:** `RealtimeBloc`

## Overview

A persistent realtime connection (WebSocket/SSE) with connection status as
state and **automatic reconnection (exponential backoff)**, behind a
`RealtimeConnector` seam.

## Domain boundary

- **Owns:** connection lifecycle/status, reconnection policy, and message
  delivery.
- **Does NOT own:** one-shot HTTP (`juice_network`), message accumulation/history
  (the consumer's domain), or message schema.

## Seam

- `RealtimeConnector.connect() → RealtimeConnection` — **one connect attempt =
  one connection**. Throwing means the attempt failed (the bloc backs off).
- `RealtimeConnection`: `messages` (inbound stream; **closes when the connection
  drops** — the bloc's drop signal), `send`, `close`.
- Default `WebSocketRealtimeConnector` (`web_socket_channel`). SSE / vendor SDKs
  implement the same seam; read-only transports throw from `send`.

## Message delivery (state + stream)

Realtime deliberately exposes a stream *as well as* state:

- **`bloc.messages`** — broadcast stream of every message, in order (chat/feeds).
- **`state.lastMessage` + `RealtimeGroups.message`** — the latest only.

Connection status is plain state (`RealtimeGroups.status`).

## Reconnection (the concurrency core)

The bloc owns the live connection, its message subscription, and the reconnect
timer (lifecycle resources, released in `close()`).

- On drop/failure → `ConnectionLostEvent`. If a **manual** disconnect →
  `disconnected`. Else attempt = `reconnectAttempts + 1`; if within
  `maxReconnectAttempts` → schedule a reconnect at
  `min(maxBackoff, initialBackoff · 2^(attempt-1))` and go `reconnecting`;
  otherwise **give up loudly** (`emitFailure`, `disconnected` + `lastError`).
- A scheduled `ReconnectEvent` preserves the attempt count; a user `ConnectEvent`
  resets it to 0. A successful connect resets attempts on
  `ConnectionEstablishedEvent`.
- `disconnect()` sets a manual-close flag and cancels any pending reconnect, so a
  late drop can't trigger a reconnect.

## State

```dart
enum RealtimeStatus { disconnected, connecting, connected, reconnecting }

class RealtimeState extends BlocState {
  final RealtimeStatus status;
  final RealtimeMessage? lastMessage;
  final int reconnectAttempts;
  final int messageCount;
  final String? lastError;
}
```

## Events

`InitializeRealtimeEvent`, `ConnectEvent`, `DisconnectEvent`, `SendEvent`,
`ReconnectEvent`*, `ConnectionEstablishedEvent`*, `ConnectionLostEvent`*,
`MessageReceivedEvent`*. (*internal)

## Fail-loud

`send()` while not connected → `emitFailure` with `lastError`, never a silent
drop. Reconnect exhaustion → `emitFailure`, never silent infinite retry.

## Testing

Headless with a fake connector + fake connection: connect→connected, message →
`lastMessage`/count/stream, send forwards, send-while-disconnected fail-loud,
drop → reconnecting → reconnect (fresh connection, attempts reset), give-up after
`maxReconnectAttempts`, manual disconnect suppresses reconnect, close disposes
connector. 9 tests.

## Scope

0.1 ships the WebSocket default. SSE and topic multiplexing fit behind the
existing seam and are planned post-0.1.

## Spec Version

| Version | Date | Status |
|---|---|---|
| 1.0 | 2026-05-28 | Implemented |
