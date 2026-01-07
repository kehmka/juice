# juice_location

> Canonical specification for the juice_location companion package

## Purpose

Location services with geofencing, background tracking, and geocoding.

---

## Dependencies

**External:**
- geolocator

**Juice Packages:**
- juice_connectivity - Check before location requests

---

## Architecture

### Bloc: `LocationBloc`

**Lifecycle:** Permanent

### State

```dart
class LocationState extends BlocState {
  final Position? currentPosition;
  final LocationPermission permissionStatus;
  final bool isTracking;
  final List<Geofence> activeGeofences;
  final List<GeofenceEvent> recentGeofenceEvents;
  final LocationError? lastError;
  final LocationAccuracy accuracy;
}
```

### Events

- `RequestPermissionEvent` - Request location permission
- `GetCurrentLocationEvent` - One-time location fetch
- `StartTrackingEvent` - Start continuous tracking
- `StopTrackingEvent` - Stop tracking
- `AddGeofenceEvent` - Create geofence
- `GeocodeAddressEvent` - Address to coordinates

### Rebuild Groups

- `location:position` - Position updates
- `location:permission` - Permission changes
- `location:geofences` - Geofence list changes

---

## Integration Points

**StateRelay to:**
- juice_analytics - Location events

---

## Open Questions

_To be discussed_
