import 'package:juice/juice.dart';

import '../adapters/adapters.dart';
import '../cache/cache_index.dart';
import '../storage_bloc.dart';
import '../storage_events.dart';
import '../storage_exceptions.dart';
import '../storage_state.dart';

/// Use case for opening a Hive box.
class HiveOpenBoxUseCase extends BlocUseCase<StorageBloc, HiveOpenBoxEvent> {
  @override
  Future<void> execute(HiveOpenBoxEvent event) async {
    try {
      final adapter = await HiveAdapterFactory.open<dynamic>(
        event.boxName,
        lazy: event.lazy,
      );

      emitUpdate(
        newState: () {
          final boxes = Map<String, BoxInfo>.from(bloc.state.hiveBoxes);
          boxes[event.boxName] = BoxInfo(
            name: event.boxName,
            isLazy: event.lazy,
            entryCount: adapter.length,
          );
          return bloc.state.copyWith(hiveBoxes: boxes);
        }(),
        groupsToRebuild: {StorageBloc.groupHive(event.boxName)},
      );

      event.succeed(null);
    } catch (e, st) {
      emitFailure(error: e, errorStackTrace: st);
      event.fail(
        StorageException(
          'Failed to open Hive box: ${event.boxName}',
          type: StorageErrorType.backendNotAvailable,
          cause: e,
        ),
        st,
      );
    }
  }
}

/// Use case for closing a Hive box.
class HiveCloseBoxUseCase extends BlocUseCase<StorageBloc, HiveCloseBoxEvent> {
  @override
  Future<void> execute(HiveCloseBoxEvent event) async {
    try {
      await HiveAdapterFactory.close(event.boxName);

      emitUpdate(
        newState: () {
          final boxes = Map<String, BoxInfo>.from(bloc.state.hiveBoxes);
          boxes.remove(event.boxName);
          return bloc.state.copyWith(hiveBoxes: boxes);
        }(),
        groupsToRebuild: {StorageBloc.groupHive(event.boxName)},
      );

      event.succeed(null);
    } catch (e, st) {
      emitFailure(error: e, errorStackTrace: st);
      event.fail(
        StorageException(
          'Failed to close Hive box: ${event.boxName}',
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
        // Lazy eviction: delete expired data
        await adapter.delete(event.key);
        await cacheIndex.removeExpiry(storageKey);

        // Emit rebuild group for the box
        emitUpdate(
          groupsToRebuild: {
            StorageBloc.groupHive(event.box),
            StorageBloc.groupCache,
          },
        );

        // Return null for expired data (success, not failure)
        event.succeed(null);
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
class HiveWriteUseCase extends BlocUseCase<StorageBloc, HiveWriteEvent> {
  final CacheIndex cacheIndex;

  HiveWriteUseCase({required this.cacheIndex});

  @override
  Future<void> execute(HiveWriteEvent event) async {
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
class HiveDeleteUseCase extends BlocUseCase<StorageBloc, HiveDeleteEvent> {
  final CacheIndex cacheIndex;

  HiveDeleteUseCase({required this.cacheIndex});

  @override
  Future<void> execute(HiveDeleteEvent event) async {
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
