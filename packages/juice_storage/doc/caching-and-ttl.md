# Caching & TTL

juice_storage provides TTL (Time-To-Live) based caching for Hive and SharedPreferences backends. This guide explains how TTL works and how to configure cache behavior.

## TTL Support Matrix

| Backend | TTL Supported | Notes |
|---------|---------------|-------|
| SharedPreferences | Yes | Via cache metadata index |
| Hive | Yes | Via cache metadata index |
| Secure Storage | No | Secrets require explicit deletion |
| SQLite | No | Use application-level TTL columns |

## How TTL Works

### Writing with TTL

When you write data with a TTL, juice_storage stores:
1. The actual data in the backend (Hive box or SharedPreferences)
2. Expiration metadata in a dedicated cache index

```dart
// Data expires in 1 hour
await storage.prefsWrite('feature_flags', flagsJson, ttl: Duration(hours: 1));

// Data expires in 30 minutes
await storage.hiveWrite('cache', 'user_profile', profile, ttl: Duration(minutes: 30));
```

### Reading with Lazy Eviction

When reading data with an expired TTL:

1. The read operation checks the cache index for expiration metadata
2. If expired, the data AND metadata are deleted
3. The read returns `null`
4. Rebuild groups are emitted so UI can react

```dart
final flags = await storage.prefsRead<String>('feature_flags');
if (flags == null) {
  // Either never existed OR expired and was evicted
  // Fetch fresh data from API
}
```

This is called **lazy eviction** - data is cleaned up when accessed.

### Eviction Flow

```
Read Request
     │
     ▼
┌─────────────────┐
│ Check metadata  │
│ for expiration  │
└────────┬────────┘
         │
    ┌────┴────┐
    │Expired? │
    └────┬────┘
         │
    Yes  │  No
    ▼    │  ▼
┌────────┴──┐ ┌────────────┐
│Delete data│ │Return data │
│& metadata │ │            │
└─────┬─────┘ └────────────┘
      │
      ▼
┌──────────────────┐
│ Emit rebuild     │
│ groups           │
│ (cache + backend)│
└─────┬────────────┘
      │
      ▼
┌──────────────┐
│ Return null  │
└──────────────┘
```

## Background Cleanup

In addition to lazy eviction, you can enable periodic background cleanup:

```dart
StorageConfig(
  enableBackgroundCleanup: true,
  cacheCleanupInterval: Duration(minutes: 15),  // Default
)
```

Background cleanup:
- Runs at the specified interval
- Removes all expired entries proactively
- Emits rebuild groups for affected data
- Continues until the bloc is closed

### Manual Cleanup

Trigger cleanup manually:

```dart
final removedCount = await storage.cleanupExpiredCache();
print('Removed $removedCount expired entries');
```

## Cache Statistics

Track cache state via `StorageState`:

```dart
final stats = storage.state.cacheStats;

print('Total cached items: ${stats.metadataCount}');
print('Expired items: ${stats.expiredCount}');
print('Last cleanup: ${stats.lastCleanupAt}');
print('Items removed in last cleanup: ${stats.lastCleanupCleanedCount}');
```

## Practical Examples

### API Response Caching

```dart
Future<UserProfile> getUserProfile(String userId) async {
  // Try cache first
  final cached = await storage.hiveRead<String>('cache', 'profile_$userId');
  if (cached != null) {
    return UserProfile.fromJson(jsonDecode(cached));
  }

  // Fetch from API
  final profile = await api.fetchProfile(userId);

  // Cache for 30 minutes
  await storage.hiveWrite(
    'cache',
    'profile_$userId',
    jsonEncode(profile.toJson()),
    ttl: Duration(minutes: 30),
  );

  return profile;
}
```

### Feature Flags with Fallback

```dart
Future<Map<String, bool>> getFeatureFlags() async {
  final cached = await storage.prefsRead<String>('feature_flags');
  if (cached != null) {
    return Map<String, bool>.from(jsonDecode(cached));
  }

  try {
    final flags = await api.fetchFeatureFlags();
    await storage.prefsWrite(
      'feature_flags',
      jsonEncode(flags),
      ttl: Duration(hours: 1),
    );
    return flags;
  } catch (e) {
    // Return defaults if API fails and no cache
    return {'new_ui': false, 'dark_mode': true};
  }
}
```

### Session Data with Short TTL

```dart
// Cache session data for 5 minutes
await storage.hiveWrite(
  'session',
  'active_cart',
  cartJson,
  ttl: Duration(minutes: 5),
);

// On app resume, check if session is still valid
final cart = await storage.hiveRead<String>('session', 'active_cart');
if (cart == null) {
  // Session expired, show "session expired" message
}
```

## Cache Key Conventions

juice_storage uses canonical keys internally for TTL metadata:

| Backend | Pattern | Example |
|---------|---------|---------|
| SharedPreferences | `prefs:{key}` | `prefs:theme_mode` |
| Hive | `hive:{box}:{key}` | `hive:cache:user_123` |

You don't need to know these - they're used internally for the cache index.

## Best Practices

### 1. Choose Appropriate TTL Values

| Data Type | Suggested TTL |
|-----------|---------------|
| User profile | 15-30 minutes |
| API responses | 5-15 minutes |
| Feature flags | 1-4 hours |
| Static content | 24 hours |
| Session data | 5-15 minutes |

### 2. Handle null Gracefully

Always assume cached data might be `null`:

```dart
final cached = await storage.hiveRead<String>('cache', 'data');
final data = cached != null ? parseData(cached) : await fetchFreshData();
```

### 3. Don't Cache Sensitive Data with TTL

Use secure storage for sensitive data (which doesn't support TTL):

```dart
// WRONG: tokens in regular storage with TTL
await storage.prefsWrite('auth_token', token, ttl: Duration(hours: 24));

// CORRECT: tokens in secure storage
await storage.secureWrite('auth_token', token);
```

### 4. Use Appropriate Backends

- **SharedPreferences + TTL**: Simple values, settings that might change
- **Hive + TTL**: Structured data, larger cached objects

### 5. Monitor Cache Stats in Development

```dart
// Add to your debug screen
if (kDebugMode) {
  final stats = storage.state.cacheStats;
  print('Cache entries: ${stats.metadataCount}');
  print('Expired: ${stats.expiredCount}');
}
```

## Clearing Cache

Clear all cached data (preserves non-cached data):

```dart
await storage.clearAll(ClearAllOptions(
  clearHive: true,
  clearPrefs: true,
  clearSecure: false,  // Keep secure data
  clearSqlite: false,  // Keep SQLite data
));
```

Or manually cleanup specific entries:

```dart
// Delete specific cached items
await storage.hiveDelete('cache', 'user_profile');
await storage.prefsDelete('feature_flags');
```
