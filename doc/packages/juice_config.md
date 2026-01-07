# juice_config

> Canonical specification for the juice_config companion package

## Purpose

Environment configuration and feature flags with runtime toggling and remote config support.

---

## Dependencies

**External:** None

**Juice Packages:**
- juice_storage - Persist config locally

---

## Architecture

### Bloc: `ConfigBloc`

**Lifecycle:** Permanent

### State

```dart
class ConfigState extends BlocState {
  final Environment currentEnvironment;
  final Map<String, dynamic> configValues;
  final Map<String, FeatureFlag> featureFlags;
  final DateTime? lastSyncTime;
  final bool isSyncing;
}
```

### Events

- `InitializeConfigEvent` - Load config for environment
- `SyncRemoteConfigEvent` - Fetch remote config/flags
- `UpdateConfigValueEvent` - Update local config
- `ToggleFeatureFlagEvent` - Enable/disable feature
- `SwitchEnvironmentEvent` - Change environment (dev only)

### Rebuild Groups

- `config:environment` - Environment changes
- `config:flags` - Feature flag changes
- `config:values` - Config value changes

---

## Open Questions

_To be discussed_
