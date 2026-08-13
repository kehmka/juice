---
card_schema: "1.0"
package: juice_realtime
version: 0.2.0
requires:
  juice: ">=1.6.0"
  web_socket_channel: ">=3.0.0"
updated: 2026-08-12
---

# juice_realtime — AI card

> Persistent realtime connection (WebSocket/SSE) with **auto-reconnect
> (exponential backoff)** as a Juice bloc, behind a swappable `RealtimeConnector`
> seam. Read repo `AGENTS.md` for the Juice mental model + gotchas.

## Purpose

**Owns:** connection lifecycle/status, reconnection policy, message delivery.
**Does NOT own:** one-shot HTTP (`juice_network`), message accumulation/history
(your domain), or message schema.

## When to use

A live stream that must stay up and self-heal on drop — chat, presence, feeds.
For request/response use `juice_network`; for durable offline writes use
`juice_sync`.

## Install

```yaml
dependencies:
  juice_realtime: ^0.2.0
```

## Construct

Pass a `url` (builds the default `WebSocketRealtimeConnector`) **or** your own
`connector`. Supplying neither throws `ArgumentError`.

```dart
final rt = RealtimeBloc.withConfig(RealtimeConfig(
  url: 'wss://example.com/ws',          // OR connector: MyConnector()
  autoConnect: true,                     // connect on init
  initialBackoff: Duration(milliseconds: 500),  // doubles per attempt
  maxBackoff: Duration(seconds: 30),
  maxReconnectAttempts: null,            // null = retry forever; else give up loudly
));
rt.messages.listen(handle);
rt.send('{"type":"ping"}');
```

## Seams

```dart
// One connect attempt = one connection. Throw → attempt failed (bloc backs off).
abstract class RealtimeConnector {
  Future<RealtimeConnection> connect();
  Future<void> dispose();
}

// A single live connection.
abstract class RealtimeConnection {
  Stream<RealtimeMessage> get messages;  // CLOSES/errors when the link drops — the drop signal
  Future<void> send(Object data);        // read-only transports (SSE) throw UnsupportedError
  Future<void> close();
}

// RealtimeMessage(Object data, {String? event})  // event = SSE type / multiplexed topic
```

## API

```dart
void connect();                 // user-initiated; resets reconnectAttempts to 0
void disconnect();              // manual close; suppresses reconnect
void sendMessage(Object data);  // fail-loud if not connected
Stream<RealtimeMessage> get messages;  // EVERY message, in order (broadcast)
bool get isConnecting;          // a connect attempt is in flight
bool get hasConnection;
```

## Events

| Event | Concurrency | Effect |
|---|---|---|
| `InitializeRealtimeEvent(config)` | `droppable` | apply config; await auto-connect if set |
| `ConnectEvent` | `droppable` | fresh connect; reset attempts; cancel pending backoff |
| `DisconnectEvent` | `droppable` | mark manual-close, invalidate pending work, close |
| `SendEvent(data)` | `sequential` | send over live connection in FIFO order; fail-loud if not connected |
| `ReconnectEvent` *internal* | `droppable` | scheduled retry fired; **preserves** attempt count |
| `ConnectionEstablishedEvent` *internal* | `sequential` | → `connected`; reset attempts when epoch is current |
| `ConnectionLostEvent(error?)` *internal* | `droppable` | current drop/fail → reconnect or give up loudly |
| `MessageReceivedEvent(msg)` *internal* | `sequential` | current message → stream + update `lastMessage`/count |

## State

```dart
enum RealtimeStatus { disconnected, connecting, connected, reconnecting }
class RealtimeState extends BlocState {
  RealtimeStatus status; RealtimeMessage? lastMessage;
  int reconnectAttempts;        // consecutive; reset on successful connect
  int messageCount; String? lastError;
  bool get isConnected;
}
```

## Rebuild groups

| Group | Emitted when |
|---|---|
| `RealtimeGroups.status` → `realtime:status` | status / attempts / error changed |
| `RealtimeGroups.message` → `realtime:message` | a new message arrived (`lastMessage`) |

The `message` group reflects only the **latest**. For *every* message (chat),
listen to `bloc.messages` — the broadcast stream never drops one.

## Concurrency

Connect, reconnect, and disconnect are individually `droppable`, while the
shared `_connecting` flag excludes connect/reconnect across their different
runtime event types. Every attempt also owns a connection epoch. Disconnect or
a newer attempt invalidates that epoch, so stale connector results, stream
callbacks, and internal events cannot revive or mutate a superseded connection.
A user connect cancels pending backoff. Sends and inbound messages are
`sequential` to preserve FIFO order; connection-loss handling is `droppable` so
an error/done pair cannot run duplicate teardown and backoff flows.

## Recipes

```dart
// 1. Custom connector (SSE — read-only, send throws)
class SseConnector implements RealtimeConnector {
  SseConnector(this.url); final String url;
  @override Future<RealtimeConnection> connect() async => _SseConnection(await openSse(url));
  @override Future<void> dispose() async {}
}
class _SseConnection implements RealtimeConnection {
  _SseConnection(this._src);
  final EventSource _src;
  @override Stream<RealtimeMessage> get messages =>
      _src.onMessage.map((e) => RealtimeMessage(e.data, event: e.type));
  @override Future<void> send(Object data) => throw UnsupportedError('SSE is read-only');
  @override Future<void> close() async => _src.close();
}

// 2. Show connection status (selective)
class StatusDot extends StatelessJuiceWidget<RealtimeBloc> {
  StatusDot() : super(groups: {RealtimeGroups.status});
  @override Widget onBuild(BuildContext c, StreamStatus s) =>
      Icon(bloc.state.isConnected ? Icons.cloud_done : Icons.cloud_off);
}

// 3. Consume every message
rt.messages.listen((m) => chatStore.add(m.data));
```

## Testing

Headless — fake the connector and feed a controllable connection:

```dart
class FakeConnection implements RealtimeConnection {
  final _in = StreamController<RealtimeMessage>();
  Stream<RealtimeMessage> get messages => _in.stream;
  final sent = <Object>[];
  Future<void> send(Object d) async => sent.add(d);
  Future<void> close() async => _in.close();
  void deliver(Object d) => _in.add(RealtimeMessage(d));
  void drop() => _in.close();              // closing → ConnectionLostEvent
}
class FakeConnector implements RealtimeConnector {
  FakeConnection? next; int connects = 0;
  Future<RealtimeConnection> connect() async { connects++; return next = FakeConnection(); }
  Future<void> dispose() async {}
}
final rt = RealtimeBloc.withConfig(RealtimeConfig(connector: connector, autoConnect: true));
await settle();                            // Future.delayed(20ms)
expect(rt.state.status, RealtimeStatus.connected);
```

## Failure modes

- `send` while not `connected` → `emitFailure` + `lastError` (never a silent drop).
- `connect()` throws → `ConnectionLostEvent` → backoff/reconnect path.
- Connection `messages` closes/errors → drop detected → reconnect or give up.
- A connector result or callback from a superseded epoch is ignored; a late
  connection object is closed immediately.
- Reconnect exhaustion (`> maxReconnectAttempts`) → `emitFailure`, status
  `disconnected`, `lastError` set — **never** silent infinite retry.

## Anti-patterns

- ❌ Relying on `state.lastMessage` for a chat log — it's latest-only; use
  `bloc.messages`.
- ❌ Accumulating history inside this bloc — message history is your domain.
- ❌ Re-using a closed `RealtimeConnection` — each connect attempt yields a new one.
- ❌ Calling `send` on a read-only (SSE) connection — it throws `UnsupportedError`.

## Invariants

- **One connect attempt = one `RealtimeConnection`.** The bloc never reuses a
  dropped connection.
- A scheduled `ReconnectEvent` preserves `reconnectAttempts`; a user `connect()`
  resets it to 0; a successful connect resets it.
- Backoff = `min(maxBackoff, initialBackoff · 2^(attempt-1))`, attempt 1-based.
- `close()` cancels the reconnect timer + message subscription, closes the
  connection and the broadcast stream, and disposes the connector.

## See also

`SPEC.md` (design depth) · `README.md` (narrative) · repo `AGENTS.md` (framework).
</content>
