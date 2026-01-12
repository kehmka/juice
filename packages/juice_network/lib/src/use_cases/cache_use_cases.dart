import 'package:juice/juice.dart';

import '../fetch_bloc.dart';
import '../fetch_events.dart';
import '../fetch_state.dart';

/// Use case to invalidate cache entries.
class InvalidateCacheUseCase
    extends BlocUseCase<FetchBloc, InvalidateCacheEvent> {
  @override
  Future<void> execute(InvalidateCacheEvent event) async {
    int invalidatedCount = 0;

    // Invalidate by specific key
    if (event.key != null) {
      await bloc.cacheManager.delete(event.key!);
      invalidatedCount = 1;
    }

    // Invalidate by URL pattern
    if (event.urlPattern != null) {
      invalidatedCount +=
          await bloc.cacheManager.deletePattern(event.urlPattern!);
    }

    // Update cache stats
    emitUpdate(
      groupsToRebuild: {FetchGroups.cache},
      newState: bloc.state.copyWith(
        cacheStats: CacheStats(
          entryCount: bloc.state.cacheStats.entryCount - invalidatedCount,
          totalBytes: bloc.state.cacheStats.totalBytes,
          expiredCount: bloc.state.cacheStats.expiredCount,
        ),
      ),
    );
  }
}

/// Use case to clear all cache entries.
class ClearCacheUseCase extends BlocUseCase<FetchBloc, ClearCacheEvent> {
  @override
  Future<void> execute(ClearCacheEvent event) async {
    await bloc.cacheManager.clear();

    emitUpdate(
      groupsToRebuild: {FetchGroups.cache},
      newState: bloc.state.copyWith(
        cacheStats: const CacheStats(),
      ),
    );
  }
}

/// Use case to prune cache to target size.
class PruneCacheUseCase extends BlocUseCase<FetchBloc, PruneCacheEvent> {
  @override
  Future<void> execute(PruneCacheEvent event) async {
    // Remove expired first if requested
    if (event.removeExpiredFirst) {
      await bloc.cacheManager.cleanupExpired();
    }

    // LRU eviction is handled by CacheManager internally
    // For now, we just trigger cleanup
    emitUpdate(
      groupsToRebuild: {FetchGroups.cache},
      newState: bloc.state,
    );
  }
}

/// Use case to clean up expired cache entries.
class CleanupExpiredCacheUseCase
    extends BlocUseCase<FetchBloc, CleanupExpiredCacheEvent> {
  @override
  Future<void> execute(CleanupExpiredCacheEvent event) async {
    final removed = await bloc.cacheManager.cleanupExpired();

    emitUpdate(
      groupsToRebuild: {FetchGroups.cache},
      newState: bloc.state.copyWith(
        cacheStats: CacheStats(
          entryCount: bloc.state.cacheStats.entryCount - removed,
          totalBytes: bloc.state.cacheStats.totalBytes,
          expiredCount: 0,
        ),
      ),
    );
  }
}
