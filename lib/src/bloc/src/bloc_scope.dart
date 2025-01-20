import '../bloc.dart';
import 'dart:collection';

typedef BlocFactory<TBloc> = TBloc Function();

String typeKey<T>() => T.toString();

class BlocScope {
  // Factory map for creating blocs dynamically.
  static final Map<String, BlocFactory> _blocFactories = {};

  // Singleton instance map for managing single-instance blocs.
  static final Map<String, JuiceBloc> _instances = {};

  // LRU cache for storing active blocs with eviction.
  static final Map<String, LinkedHashMap<dynamic, JuiceBloc>> _lruCaches = {};

  // Register a factory for bloc creation.
  static void registerFactory<TBloc extends JuiceBloc>(
      BlocFactory<TBloc> factory) {
    final type = TBloc;
    JuiceLoggerConfig.logger.log("Registering bloc factory", context: {
      'action': 'register_factory',
      'blocType': type.toString(),
      'totalFactories': _blocFactories.length + 1,
    });
    _blocFactories[typeKey<TBloc>()] = factory;
  }

  // Retrieve or create a bloc instance
  static TBloc get<TBloc extends JuiceBloc>({
    dynamic key, // Optional key for scoped instances
    int maxCacheSize = 100,
    bool singleton = true, // Default to singleton behavior
  }) {
    final type = TBloc;
    final typeStr = typeKey<TBloc>();

    // Singleton handling: Return existing instance if present
    if (singleton) {
      if (_instances.containsKey(typeStr)) {
        JuiceLoggerConfig.logger.log('Returning singleton instance', context: {
          'action': 'get_singleton',
          'blocType': type.toString(),
          'instanceExists': true,
        });
        return _instances[typeStr] as TBloc;
      }
    } else {
      // Ensure the LRU cache exists for the type
      _lruCaches.putIfAbsent(
          typeStr, () => LinkedHashMap<dynamic, JuiceBloc>());
      final cache = _lruCaches[typeStr]!;

      // Default behavior if no key is provided
      key ??= 'default';

      // Check if the instance already exists in the cache
      if (cache.containsKey(key)) {
        JuiceLoggerConfig.logger.log('Cache hit', context: {
          'action': 'get_cached',
          'blocType': type.toString(),
          'key': key.toString(),
          'cacheSize': cache.length,
        });
        return cache[key] as TBloc;
      }
    }

    // Create a new bloc using the factory
    final factory = _blocFactories[typeStr];
    if (factory == null) {
      final error = Exception('Bloc factory not registered');
      JuiceLoggerConfig.logger.logError(
          'Factory lookup failed', error, StackTrace.current,
          context: {
            'action': 'factory_lookup',
            'blocType': type.toString(),
            'registeredTypes': _blocFactories.keys.toList(),
          });
      throw error;
    }

    final bloc = factory();
    if (singleton) {
      // Store the singleton instance
      _instances[typeStr] = bloc;
      JuiceLoggerConfig.logger.log('Created singleton instance', context: {
        'action': 'create_singleton',
        'blocType': type.toString(),
        'totalSingletons': _instances.length,
      });
    } else {
      // Cache the new instance
      final cache = _lruCaches[typeStr]!;
      cache[key] = bloc;

      // Evict the oldest item if the cache exceeds max size
      if (cache.length > maxCacheSize) {
        final oldestKey = cache.keys.first;
        final oldestBloc = cache.remove(oldestKey);
        JuiceLoggerConfig.logger.log('Evicting cached bloc', context: {
          'action': 'cache_eviction',
          'blocType': type.toString(),
          'key': oldestKey.toString(),
          'cacheSize': cache.length,
          'maxSize': maxCacheSize,
        });
        oldestBloc?.dispose();
      }
    }
    return bloc as TBloc;
  }

  // Clear all cached blocs for a specific type.
  static void clear<TBloc extends JuiceBloc>() {
    final type = TBloc;
    final typeStr = typeKey<TBloc>();

    // Clear singleton instance
    if (_instances.containsKey(typeStr)) {
      final instance = _instances.remove(typeStr);
      JuiceLoggerConfig.logger.log('Clearing singleton', context: {
        'action': 'clear_singleton',
        'blocType': type.toString(),
        'remainingSingletons': _instances.length,
      });
      instance?.dispose();
    }

    // Clear LRU cache
    if (_lruCaches.containsKey(typeStr)) {
      final cache = _lruCaches[typeStr]!;
      JuiceLoggerConfig.logger.log('Clearing cache', context: {
        'action': 'clear_cache',
        'blocType': type.toString(),
        'clearedInstances': cache.length,
      });
      for (final bloc in cache.values) {
        bloc.dispose();
      }
      cache.clear();
      _lruCaches.remove(typeStr);
    }
  }

  // Clear all caches and instances for all bloc types.
  static void clearAll() {
    // Dispose all singleton instances
    final singletonCount = _instances.length;
    for (final instance in _instances.values) {
      instance.dispose();
    }

    // Dispose all cached instances
    var totalCached = 0;
    for (final cache in _lruCaches.values) {
      totalCached += cache.length;
      for (final bloc in cache.values) {
        bloc.dispose();
      }
      cache.clear();
    }

    JuiceLoggerConfig.logger.log('Cleared all blocs', context: {
      'action': 'clear_all',
      'singletonsCleared': singletonCount,
      'cachesCleared': _lruCaches.length,
      'totalInstancesCleared': singletonCount + totalCached,
    });

    _instances.clear();
    _lruCaches.clear();
  }
}
