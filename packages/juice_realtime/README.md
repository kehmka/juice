# juice_realtime

Persistent realtime connections (WebSocket/SSE) with **automatic reconnection**,
as a [Juice](https://pub.dev/packages/juice) bloc, behind a swappable seam.

[![pub package](https://img.shields.io/pub/v/juice_realtime.svg)](https://pub.dev/packages/juice_realtime)
[![License: MIT](https://img.shields.io/badge/license-MIT-purple.svg)](LICENSE)

## What it owns

A persistent connection's **status** and **message delivery**, with reconnect/
backoff. It does **not** own one-shot HTTP (that's `juice_network`) or message
*accumulation* (chat history is your domain — listen to `messages` and store).

## Install

```yaml
dependencies:
  juice_realtime: ^0.1.0
```

## Use

```dart
final rt = RealtimeBloc.withConfig(RealtimeConfig(url: 'wss://example.com/ws'));

rt.messages.listen((m) => print(m.data));  // every message, in order
rt.sendMessage('{"type":"ping"}');
rt.disconnect();                            // stops reconnection
```

## Two ways to read messages

Realtime is the one place the family exposes a **stream** as well as state, on
purpose — high-frequency consumers must not drop messages:

- **`bloc.messages`** — a broadcast stream of *every* message, in order. Use for
  chat, feeds, anything that accumulates.
- **`state.lastMessage` + `RealtimeGroups.message`** — the *latest* message, for
  a simple "live value" widget:

```dart
class Ticker extends StatelessJuiceWidget<RealtimeBloc> {
  Ticker({super.key}) : super(groups: {RealtimeGroups.message});
  @override
  Widget onBuild(BuildContext context, StreamStatus status) =>
      Text('${bloc.state.lastMessage?.data ?? '—'}');
}
```

Connection status is plain state — bind `RealtimeGroups.status`:

```dart
class ConnDot extends StatelessJuiceWidget<RealtimeBloc> {
  ConnDot({super.key}) : super(groups: {RealtimeGroups.status});
  @override
  Widget onBuild(BuildContext context, StreamStatus status) =>
      Icon(Icons.circle, color: bloc.state.isConnected ? Colors.green : Colors.red);
}
```

## Reconnection

A dropped connection reconnects automatically with exponential backoff:

```dart
RealtimeConfig(
  url: 'wss://example.com/ws',
  initialBackoff: Duration(seconds: 1),
  maxBackoff: Duration(seconds: 30),
  maxReconnectAttempts: 8,   // null = forever
);
```

`status` moves `connecting → connected → reconnecting → …`; after
`maxReconnectAttempts` it gives up **loudly** (`disconnected` + `lastError`).
`disconnect()` is a user-initiated close and suppresses reconnection.

## The seam (WebSocket, SSE, or a vendor SDK)

The bloc depends on `RealtimeConnector`, not on a socket library. Default is
`WebSocketRealtimeConnector` (`web_socket_channel`). Implement the seam for SSE,
a vendor SDK, or tests:

```dart
abstract class RealtimeConnector {
  Future<RealtimeConnection> connect();  // one attempt; throws → bloc backs off
  Future<void> dispose();
}
abstract class RealtimeConnection {
  Stream<RealtimeMessage> get messages;  // closes when the connection drops
  Future<void> send(Object data);        // read-only transports throw
  Future<void> close();
}
```

## Fail-loud send

`send()` while not connected sets `state.lastError` and emits a failure — it does
not silently swallow the payload.

## State

| Field | Meaning |
|---|---|
| `status` | disconnected / connecting / connected / reconnecting |
| `lastMessage` | latest message (see `messages` for all) |
| `reconnectAttempts` | consecutive failed reconnects (reset on success) |
| `messageCount` | total received this session |
| `lastError` | last connection/send error |

## License

MIT License — see [LICENSE](LICENSE).
