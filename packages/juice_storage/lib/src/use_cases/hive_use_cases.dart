import 'package:juice/juice.dart';

import '../adapters/adapters.dart';
import '../cache/cache_index.dart';
import '../storage_bloc.dart';
import '../storage_events.dart';
import '../storage_exceptions.dart';
import '../storage_state.dart';
import 'serialized_storage_mutation_use_case.dart';

/// Use case for opening a Hive box.
class HiveOpenBoxUseCase
    extends SerializedStorageMutationUseCase<HiveOpenBoxEvent> {
  @override
  Future<void> executeMutation(HiveOpenBoxEvent event) async {
    try {
      final adapter = await HiveAdapterFactory.open<dynamic>(
        event.box,
        lazy: event.lazy,
      );

      emitUpdate(
        newState: () {
          final boxes = Map<String, BoxInfo>.from(bloc.state.hiveBoxes);
          boxes[event.box] = BoxInfo(
            name: event.box,
            isLazy: event.lazy,
            entryCount: adapter.length,
          );
          return bloc.state.copyWith(hiveBoxes: boxes);
        }(),
        groupsToRebuild: {StorageBloc.groupHive(event.box)},
      );

      event.succeed(null);
    } catch (e, st) {
      emitFailure(error: e, errorStackTrace: st);
      event.fail(
        StorageException(
          'Failed to open Hive box: ${event.box}',
          type: StorageErrorType.backendNotAvailable,
          cause: e,
        ),
        st,
      );
    }
  }
}

/// Use case for closing a Hive box.
class HiveCloseBoxUseCase
    extends SerializedStorageMutationUseCase<HiveCloseBoxEvent> {
  @override
  Future<void> executeMutation(HiveCloseBoxEvent event) async {
    try {
      await HiveAdapterFactory.close(event.box);

      emitUpdate(
        newState: () {
          final boxes = Map<String, BoxInfo>.from(bloc.state.hiveBoxes);
          boxes.remove(event.box);
          return bloc.state.copyWith(hiveBoxes: boxes);
        }(),
        groupsToRebuild: {StorageBloc.groupHive(event.box)},
      );

      event.succeed(null);
    } catch (e, st) {
      emitFailure(error: e, errorStackTrace: st);
      event.fail(
        StorageException(
          'Failed to close Hive box: ${event.box}',
          type: StorageErrorType.backendNotAvailable,
          cause: e,
        ),
        st,
      );
    }
  }
}

/// Use case for reading from Hive with TTL check.
class HiveReadUseCase extends BlocUseCase<StorageBloc, HiveReadEvent> {
  final CacheIndex cacheIndex;

  HiveReadUseCase({required this.cacheIndex});

  @override
  Future<void> execute(HiveReadEvent event) async {
    try {
      final adapter = HiveAdapterFactory.get<dynamic>(event.box);
      if (adapter == null) {
        throw StorageException(
          'Hive box not open: ${event.box}',
          type: StorageErrorType.boxNotOpen,
        );
      }

      // Check TTL expiration
      final storageKey = cacheIndex.canonicalKey('hive', event.key, event.box);
      if (cacheIndex.isExpired(storageKey)) {
        // The query stays concurrent until it discovers expired data. Lazy
        // eviction is a mutation and must join the shared mutation FIFO.
        await bloc.runStorageMutation(() async {
          // A mutation queued before this read may have refreshed the value.
          // Re-check inside the FIFO before deleting anything.
          if (!cacheIndex.isExpired(storageKey)) {
            final value = await adapter.read(event.key);
            emitUpdate();
            event.succeed(value);
            return;
          }

          await adapter.delete(event.key);
          await cacheIndex.removeExpiry(storageKey);

          emitUpdate(
            groupsToRebuild: {
              StorageBloc.groupHive(event.box),
              StorageBloc.groupCache,
            },
          );
          event.succeed(null);
        });
        return;
      }

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
            'Failed to read from Hive: ${event.box}/${event.key}',
            type: StorageErrorType.backendNotAvailable,
            cause: e,
          ),
          st,
        );
      }
    }
  }
}

/// Use case for writing to Hive with optional TTL.
class HiveWriteUseCase
    extends SerializedStorageMutationUseCase<HiveWriteEvent> {
  final CacheIndex cacheIndex;

  HiveWriteUseCase({required this.cacheIndex});

  @override
  Future<void> executeMutation(HiveWriteEvent event) async {
    try {
      final adapter = HiveAdapterFactory.get<dynamic>(event.box);
      if (adapter == null) {
        throw StorageException(
          'Hive box not open: ${event.box}',
          type: StorageErrorType.boxNotOpen,
        );
      }

      final storageKey = cacheIndex.canonicalKey('hive', event.key, event.box);

      // Null value = delete (common cache semantics)
      if (event.value == null) {
        await adapter.delete(event.key);
        await cacheIndex.removeExpiry(storageKey);
      } else {
        await adapter.write(event.key, event.value);

        // Set TTL if provided
        if (event.ttl != null) {
          await cacheIndex.setExpiry(storageKey, event.ttl!);
        } else {
          // Remove any existing TTL
          await cacheIndex.removeExpiry(storageKey);
        }
      }

      // Update entry count in state
      emitUpdate(
        newState: () {
          final boxes = Map<String, BoxInfo>.from(bloc.state.hiveBoxes);
          final currentBox = boxes[event.box];
          if (currentBox != null) {
            boxes[event.box] = BoxInfo(
              name: currentBox.name,
              isLazy: currentBox.isLazy,
              entryCount: adapter.length,
            );
          }
          return bloc.state.copyWith(hiveBoxes: boxes);
        }(),
        groupsToRebuild: {StorageBloc.groupHive(event.box)},
      );

      event.succeed(null);
    } catch (e, st) {
      emitFailure(error: e, errorStackTrace: st);
      if (e is StorageException) {
        event.fail(e, st);
      } else {
        event.fail(
          StorageException(
            'Failed to write to Hive: ${event.box}/${event.key}',
            type: StorageErrorType.backendNotAvailable,
            cause: e,
          ),
          st,
        );
      }
    }
  }
}

/// Use case for deleting from Hive.
class HiveDeleteUseCase
    extends SerializedStorageMutationUseCase<HiveDeleteEvent> {
  final CacheIndex cacheIndex;

  HiveDeleteUseCase({required this.cacheIndex});

  @override
  Future<void> executeMutation(HiveDeleteEvent event) async {
    try {
      final adapter = HiveAdapterFactory.get<dynamic>(event.box);
      if (adapter == null) {
        throw StorageException(
          'Hive box not open: ${event.box}',
          type: StorageErrorType.boxNotOpen,
        );
      }

      await adapter.delete(event.key);

      // Remove TTL metadata
      final storageKey = cacheIndex.canonicalKey('hive', event.key, event.box);
      await cacheIndex.removeExpiry(storageKey);

      // Update entry count
      emitUpdate(
        newState: () {
          final boxes = Map<String, BoxInfo>.from(bloc.state.hiveBoxes);
          final currentBox = boxes[event.box];
          if (currentBox != null) {
            boxes[event.box] = BoxInfo(
              name: currentBox.name,
              isLazy: currentBox.isLazy,
              entryCount: adapter.length,
            );
          }
          return bloc.state.copyWith(hiveBoxes: boxes);
        }(),
        groupsToRebuild: {StorageBloc.groupHive(event.box)},
      );

      event.succeed(null);
    } catch (e, st) {
      emitFailure(error: e, errorStackTrace: st);
      if (e is StorageException) {
        event.fail(e, st);
      } else {
        event.fail(
          StorageException(
            'Failed to delete from Hive: ${event.box}/${event.key}',
            type: StorageErrorType.backendNotAvailable,
            cause: e,
          ),
          st,
        );
      }
    }
  }
}

/// Use case for getting all keys from a Hive box.
class HiveKeysUseCase extends BlocUseCase<StorageBloc, HiveKeysEvent> {
  @override
  Future<void> execute(HiveKeysEvent event) async {
    try {
      final adapter = HiveAdapterFactory.get<dynamic>(event.box);
      if (adapter == null) {
        throw StorageException(
          'Hive box not open: ${event.box}',
          type: StorageErrorType.boxNotOpen,
        );
      }

      final keys = await adapter.keys();
      emitUpdate();
      event.succeed(keys.toList());
    } catch (e, st) {
      emitFailure(error: e, errorStackTrace: st);
      if (e is StorageException) {
        event.fail(e, st);
      } else {
        event.fail(
          StorageException(
            'Failed to get keys from Hive: ${event.box}',
            type: StorageErrorType.backendNotAvailable,
            cause: e,
          ),
          st,
        );
      }
    }
  }
}
