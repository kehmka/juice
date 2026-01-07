import 'package:juice/juice.dart';

import '../adapters/adapters.dart';
import '../cache/cache_index.dart';
import '../cache/cache_stats.dart';
import '../storage_bloc.dart';
import '../storage_events.dart';
import '../storage_exceptions.dart';
import '../storage_state.dart';

/// Use case for cleaning up expired cache entries.
///
/// This performs eager cleanup by iterating through all expired entries
/// in the cache index and deleting them from their respective backends.
class CacheCleanupUseCase extends BlocUseCase<StorageBloc, CacheCleanupEvent> {
  final CacheIndex cacheIndex;

  CacheCleanupUseCase({required this.cacheIndex});

  @override
  Future<void> execute(CacheCleanupEvent event) async {
    try {
      if (!event.runNow) {
        // If not running now, just succeed (interval setup handled elsewhere)
        event.succeed(0);
        return;
      }

      final expiredEntries = cacheIndex.getExpiredEntries();
      var cleaned = 0;
      final groupsToRebuild = <String>{};

      for (final meta in expiredEntries) {
        try {
          // Parse storage key to determine backend
          final parts = meta.storageKey.split(':');
          if (parts.isEmpty) continue;

          final backend = parts[0];
          var deleted = false;

          switch (backend) {
            case 'hive':
              if (parts.length >= 3) {
                final box = parts[1];
                final key = parts.sublist(2).join(':');
                final adapter = HiveAdapterFactory.get<dynamic>(box);
                if (adapter != null) {
                  await adapter.delete(key);
                  groupsToRebuild.add(StorageBloc.groupHive(box));
                  deleted = true;
                }
              }
              break;

            case 'prefs':
              if (parts.length >= 2) {
                final key = parts.sublist(1).join(':');
                final adapter = PrefsAdapterFactory.instance;
                if (adapter != null) {
                  await adapter.delete(key);
                  groupsToRebuild.add(StorageBloc.groupPrefs);
                  deleted = true;
                }
              }
              break;

            // Note: SQLite and Secure don't support TTL
          }

          // Only remove metadata and count as cleaned if data was actually deleted
          if (deleted) {
            await cacheIndex.removeExpiry(meta.storageKey);
            cleaned++;
          }
        } catch (_) {
          // Continue on individual entry failure
        }
      }

      // Update cache stats
      final newStats = CacheStats(
        metadataCount: cacheIndex.metadataCount,
        expiredCount: cacheIndex.expiredCount,
        lastCleanupAt: DateTime.now(),
        lastCleanupCleanedCount: cleaned,
      );

      groupsToRebuild.add(StorageBloc.groupCache);

      emitUpdate(
        newState: bloc.state.copyWith(cacheStats: newStats),
        groupsToRebuild: groupsToRebuild,
      );

      event.succeed(cleaned);
    } catch (e, st) {
      emitFailure(error: e, errorStackTrace: st);
      event.fail(
        StorageException(
          'Cache cleanup failed',
          type: StorageErrorType.backendNotAvailable,
          cause: e,
        ),
        st,
      );
    }
  }
}
