# juice_messaging

> Canonical specification for the juice_messaging companion package

## Purpose

WebSocket-based real-time messaging with automatic reconnection.

---

## Dependencies

**External:** None

**Juice Packages:**
- juice_network - Optional REST fallback
- juice_connectivity - Monitor connection for reconnect

---

## Architecture

### Bloc: `MessagingBloc`

**Lifecycle:** Permanent

### State

```dart
class MessagingState extends BlocState {
  final ConnectionStatus status; // disconnected, connecting, connected, reconnecting
  final List<Message> messages;
  final List<Channel> subscribedChannels;
  final Map<String, MessageStatus> pendingMessages;
  final String? lastError;
  final int reconnectAttempts;
}
```

### Events

- `ConnectEvent` - Establish WebSocket connection
- `DisconnectEvent` - Close connection
- `SendMessageEvent` - Send message to channel
- `ReceiveMessageEvent` - Message received
- `SubscribeChannelEvent` - Subscribe to channel

### Rebuild Groups

- `messaging:status` - Connection status
- `messaging:channel:{id}` - Per-channel messages
- `messaging:pending` - Pending message status

---

## Integration Points

**StateRelay from:**
- juice_connectivity - Auto-reconnect
- juice_auth - Authenticated connections

---

## Open Questions

_To be discussed_
