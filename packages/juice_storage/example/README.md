# Storage Arcade - juice_storage Example

An interactive demo app showcasing all features of the `juice_storage` package.

## Features Demonstrated

- **Multiple Storage Backends**: Hive, SharedPreferences, SQLite, and Secure Storage
- **TTL Caching**: Create entries with configurable TTL and watch them expire
- **Automatic Eviction**: Background cleanup removes expired entries in real-time
- **Live Event Log**: See all storage events as they happen
- **Storage Inspector**: Browse contents of all storage backends

## Running the Example

```bash
cd packages/juice_storage/example
flutter run
```

## Screens

### Arcade Screen
Interactive storage playground:
- Create entries with different backends
- Set TTL values and watch countdown timers
- Spawn "time bombs" (entries with short TTL)
- Manual cache cleanup trigger
- Cumulative eviction tracking by backend

### Inspector Screen
Storage browser:
- View all Hive boxes and their contents
- Browse SharedPreferences entries
- Query SQLite tables
- Check Secure Storage keys
