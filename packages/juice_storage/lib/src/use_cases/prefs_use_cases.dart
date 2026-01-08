import 'package:juice/juice.dart';

import '../adapters/adapters.dart';
import '../cache/cache_index.dart';
import '../storage_bloc.dart';
import '../storage_events.dart';
import '../storage_exceptions.dart';
import '../storage_state.dart';

/// Use case for reading from SharedPreferences with TTL check.
///
/// Implements lazy eviction: if the key is expired, delete it and return null.
/// Emits rebuild groups on expiration to notify observers.
class PrefsReadUseCase extends BlocUseCase<StorageBloc, PrefsReadEvent> {
  final CacheIndex cacheIndex;

  PrefsReadUseCase({required this.cacheIndex});

  @override
  Future<void> execute(PrefsReadEvent event) async {
    try {
      final adapter = PrefsAdapterFactory.instance;
      if (adapter == null) {
        throw StorageException(
          'SharedPreferences not initialized',
          type: StorageErrorType.notInitialized,
        );
      }

      // Check TTL expiration (uses logical key)
      final storageKey = cacheIndex.canonicalKey('prefs', event.key);
      if (cacheIndex.isExpired(storageKey)) {
        // Step 1: Delete expired data (adapter handles prefixing)
        await adapter.delete(event.key);

        // Step 2: Remove cache metadata
        await cacheIndex.removeExpiry(storageKey);

        // Step 3: Emit rebuild groups for observers
        emitUpdate(
          groupsToRebuild: {StorageBloc.groupPrefs, StorageBloc.groupCache},
        );

        // Step 4: Return null successfully (expired = no value)
        event.succeed(null);
        return;
      }

      // Not expired: read and return value
      final value = await adapter.read(event.key);

      // Emit status for sendAndWaitResult, but no rebuild groups (reads don't trigger rebuilds)
      emitUpdate();
      event.succeed(value);
    } catch (e, st) {
      emitFailure(error: e, errorStackTrace: st);
      if (e is StorageException) {
        event.fail(e, st);
      } else {
        event.fail(
          StorageException(
            'Failed to read from SharedPreferences: ${event.key}',
            type: StorageErrorType.backendNotAvailable,
            cause: e,
          ),
          st,
        );
      }
    }
  }
}

/// Use case for writing to SharedPreferences with optional TTL.
class PrefsWriteUseCase extends BlocUseCase<StorageBloc, PrefsWriteEvent> {
  final CacheIndex cacheIndex;

  PrefsWriteUseCase({required this.cacheIndex});

  @override
  Future<void> execute(PrefsWriteEvent event) async {
    try {
      final adapter = PrefsAdapterFactory.instance;
      if (adapter == null) {
        throw StorageException(
          'SharedPreferences not initialized',
          type: StorageErrorType.notInitialized,
        );
      }

      // Write value (adapter handles prefixing)
      if (event.value == null) {
        throw StorageException(
          'Cannot write null value to SharedPreferences',
          type: StorageErrorType.typeError,
          storageKey: event.key,
        );
      }
      await adapter.write(event.key, event.value!);

      // Set or remove TTL
      final storageKey = cacheIndex.canonicalKey('prefs', event.key);
      if (event.ttl != null) {
        await cacheIndex.setExpiry(storageKey, event.ttl!);
      } else {
        await cacheIndex.removeExpiry(storageKey);
      }

      emitUpdate(
        groupsToRebuild: {StorageBloc.groupPrefs},
      );

      event.succeed(null);
    } catch (e, st) {
      emitFailure(error: e, errorStackTrace: st);
      if (e is StorageException) {
        event.fail(e, st);
      } else {
        event.fail(
          StorageException(
            'Failed to write to SharedPreferences: ${event.key}',
            type: StorageErrorType.backendNotAvailable,
            cause: e,
          ),
          st,
        );
      }
    }
  }
}

/// Use case for deleting from SharedPreferences.
class PrefsDeleteUseCase extends BlocUseCase<StorageBloc, PrefsDeleteEvent> {
  final CacheIndex cacheIndex;

  PrefsDeleteUseCase({required this.cacheIndex});

  @override
  Future<void> execute(PrefsDeleteEvent event) async {
    try {
      final adapter = PrefsAdapterFactory.instance;
      if (adapter == null) {
        throw StorageException(
          'SharedPreferences not initialized',
          type: StorageErrorType.notInitialized,
        );
      }

      // Delete value (adapter handles prefixing)
      await adapter.delete(event.key);

      // Remove TTL metadata
      final storageKey = cacheIndex.canonicalKey('prefs', event.key);
      await cacheIndex.removeExpiry(storageKey);

      emitUpdate(
        groupsToRebuild: {StorageBloc.groupPrefs},
      );

      event.succeed(null);
    } catch (e, st) {
      emitFailure(error: e, errorStackTrace: st);
      if (e is StorageException) {
        event.fail(e, st);
      } else {
        event.fail(
          StorageException(
            'Failed to delete from SharedPreferences: ${event.key}',
            type: StorageErrorType.backendNotAvailable,
            cause: e,
          ),
          st,
        );
      }
    }
  }
}
