# juice_connectivity

> Canonical specification for the juice_connectivity companion package

## Purpose

Network and Bluetooth connectivity monitoring with automatic state updates.

---

## Dependencies

**External:**
- connectivity_plus
- flutter_blue_plus

**Juice Packages:** None

---

## Architecture

### Bloc: `ConnectivityBloc`

**Lifecycle:** Permanent

### State

```dart
class ConnectivityState extends BlocState {
  final NetworkStatus networkStatus;
  final BluetoothStatus bluetoothStatus;
  final bool hasInternet;
  final List<BluetoothDevice> discoveredDevices;
  final BluetoothDevice? connectedDevice;
  final DateTime? lastConnectivityCheck;
}
```

### Events

- `InitializeConnectivityEvent` - Start monitoring
- `ConnectivityChangedEvent` - Network status changed
- `CheckConnectivityEvent` - Force connectivity check
- `StartBluetoothScanEvent` - Discover devices
- `ConnectBluetoothDeviceEvent` - Connect to device

### Rebuild Groups

- `connectivity:network` - Network status
- `connectivity:bluetooth` - Bluetooth status
- `connectivity:devices` - Device list changes

---

## Integration Points

**StateRelay to:**
- juice_network - Request queueing when offline
- juice_messaging - WebSocket reconnection

---

## Open Questions

_To be discussed_
