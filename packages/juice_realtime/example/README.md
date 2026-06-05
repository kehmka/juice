# juice_realtime example

A live "echo" connection, built with Juice primitives only.

Uses a `DemoRealtimeConnector` (the seam) that connects after a short delay and
echoes whatever you send back as a message — so the app runs with **no server**.

Demonstrates:
- connection status as state (the chip rebuilds only on `realtime:status`)
- latest message + count (the card rebuilds only on `realtime:message`)
- send (fail-loud when disconnected), connect/disconnect

For a real app, drop the connector for `RealtimeConfig(url: 'wss://your.host/ws')`
and listen to `bloc.messages` for the full stream.

## Run

```bash
flutter run
```
