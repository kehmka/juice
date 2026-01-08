import 'dart:math';

import 'package:juice/juice.dart';
import 'package:juice_storage/juice_storage.dart';

import '../demo_entry.dart';
import 'arcade_demo_events.dart';
import 'arcade_demo_state.dart';

/// Bloc for the Arcade demo screen.
///
/// Manages UI state and coordinates with [StorageBloc] for persistence.
/// Demonstrates proper Juice patterns:
/// - StatefulUseCaseBuilder for timer tick
/// - Cross-bloc communication via BlocScope.get()
/// - Event-driven state management
class ArcadeDemoBloc extends JuiceBloc<ArcadeDemoState> {
  ArcadeDemoBloc()
      : super(
          const ArcadeDemoState(),
          _buildUseCases(),
        );

  /// Access to storage bloc via BlocScope (cross-bloc communication).
  StorageBloc get storageBloc => BlocScope.get<StorageBloc>();

  // Rebuild groups
  static const groupEntries = 'arcade:entries';
  static const groupBanner = 'arcade:banner';
  static const groupForm = 'arcade:form';
  static const groupTime = 'arcade:time';

  static List<UseCaseBuilderGenerator> _buildUseCases() {
    return [
      // Simple state updates
      () => UseCaseBuilder(
            typeOfEvent: UpdateKeyEvent,
            useCaseGenerator: () => _UpdateKeyUseCase(),
          ),
      () => UseCaseBuilder(
            typeOfEvent: UpdateValueEvent,
            useCaseGenerator: () => _UpdateValueUseCase(),
          ),
      () => UseCaseBuilder(
            typeOfEvent: SelectBackendEvent,
            useCaseGenerator: () => _SelectBackendUseCase(),
          ),
      () => UseCaseBuilder(
            typeOfEvent: UpdateTtlEvent,
            useCaseGenerator: () => _UpdateTtlUseCase(),
          ),

      // Storage operations
      () => UseCaseBuilder(
            typeOfEvent: SaveEntryEvent,
            useCaseGenerator: () => _SaveEntryUseCase(),
          ),
      () => UseCaseBuilder(
            typeOfEvent: ReadEntryEvent,
            useCaseGenerator: () => _ReadEntryUseCase(),
          ),
      () => UseCaseBuilder(
            typeOfEvent: DeleteEntryEvent,
            useCaseGenerator: () => _DeleteEntryUseCase(),
          ),
      () => UseCaseBuilder(
            typeOfEvent: SpawnBombsEvent,
            useCaseGenerator: () => _SpawnBombsUseCase(),
          ),
      () => UseCaseBuilder(
            typeOfEvent: CleanupCacheEvent,
            useCaseGenerator: () => _CleanupCacheUseCase(),
          ),

      // Timer tick - StatefulUseCaseBuilder maintains the timer
      () => StatefulUseCaseBuilder(
            typeOfEvent: TickEvent,
            useCaseGenerator: () => _TickUseCase(),
            initialEventBuilder: () => TickEvent(),
          ),
    ];
  }
}

// --- Simple state update use cases ---

class _UpdateKeyUseCase extends BlocUseCase<ArcadeDemoBloc, UpdateKeyEvent> {
  @override
  Future<void> execute(UpdateKeyEvent event) async {
    emitUpdate(
      newState: bloc.state.copyWith(keyText: event.key),
      groupsToRebuild: {ArcadeDemoBloc.groupForm},
    );
  }
}

class _UpdateValueUseCase extends BlocUseCase<ArcadeDemoBloc, UpdateValueEvent> {
  @override
  Future<void> execute(UpdateValueEvent event) async {
    emitUpdate(
      newState: bloc.state.copyWith(valueText: event.value),
      groupsToRebuild: {ArcadeDemoBloc.groupForm},
    );
  }
}

class _SelectBackendUseCase
    extends BlocUseCase<ArcadeDemoBloc, SelectBackendEvent> {
  @override
  Future<void> execute(SelectBackendEvent event) async {
    emitUpdate(
      newState: bloc.state.copyWith(selectedBackend: event.backend),
      groupsToRebuild: {ArcadeDemoBloc.groupForm},
    );
  }
}

class _UpdateTtlUseCase extends BlocUseCase<ArcadeDemoBloc, UpdateTtlEvent> {
  @override
  Future<void> execute(UpdateTtlEvent event) async {
    emitUpdate(
      newState: bloc.state.copyWith(ttlSeconds: event.seconds),
      groupsToRebuild: {ArcadeDemoBloc.groupForm},
    );
  }
}

/// Stateful use case that manages a timer for countdown updates.
class _TickUseCase extends BlocUseCase<ArcadeDemoBloc, TickEvent> {
  Timer? _timer;

  @override
  Future<void> execute(TickEvent event) async {
    // Start timer on first tick
    _timer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      bloc.send(TickEvent());
    });

    emitUpdate(
      newState: bloc.state.copyWith(currentTime: DateTime.now()),
      groupsToRebuild: {ArcadeDemoBloc.groupTime},
    );
  }

  @override
  void close() {
    _timer?.cancel();
    _timer = null;
    super.close();
  }
}

// --- Storage operation use cases ---

class _SaveEntryUseCase extends BlocUseCase<ArcadeDemoBloc, SaveEntryEvent> {
  @override
  Future<void> execute(SaveEntryEvent event) async {
    final state = bloc.state;
    final key = state.keyText.trim();

    if (key.isEmpty) {
      emitUpdate(
        newState: state.copyWith(banner: 'Key cannot be empty'),
        groupsToRebuild: {ArcadeDemoBloc.groupBanner},
      );
      return;
    }

    final value = state.valueText;
    final backend = state.selectedBackend;
    final ttl = state.ttlSeconds <= 0
        ? null
        : Duration(seconds: state.ttlSeconds.round());

    final entry = DemoEntry(
      backend: backend,
      key: key,
      value: value,
      createdAt: DateTime.now(),
      ttl: ttl,
    );

    emitUpdate(
      newState: state.copyWith(isOperationInProgress: true),
    );

    try {
      final storage = bloc.storageBloc;

      switch (backend) {
        case DemoBackend.prefs:
          await storage.prefsWrite(key, value, ttl: ttl);
          break;
        case DemoBackend.hive:
          await storage.hiveWrite('arcade_box', key, value, ttl: ttl);
          break;
        case DemoBackend.secure:
          await storage.secureWrite(key, value);
          break;
        case DemoBackend.sqlite:
          await storage.sqliteRaw(
            'CREATE TABLE IF NOT EXISTS kv (k TEXT PRIMARY KEY, v TEXT)',
          );
          await storage.sqliteRaw(
            'INSERT OR REPLACE INTO kv(k,v) VALUES(?,?)',
            [key, value],
          );
          break;
      }

      final newEntries = [entry, ...bloc.state.entries];
      final ttlMsg = ttl != null ? ' (TTL: ${ttl.inSeconds}s)' : ' (no TTL)';

      emitUpdate(
        newState: bloc.state.copyWith(
          entries: newEntries,
          banner: 'SAVED ${backend.name}:$key$ttlMsg',
          isOperationInProgress: false,
        ),
        groupsToRebuild: {ArcadeDemoBloc.groupEntries, ArcadeDemoBloc.groupBanner},
      );
    } catch (e) {
      emitUpdate(
        newState: bloc.state.copyWith(
          banner: 'ERROR: $e',
          isOperationInProgress: false,
        ),
        groupsToRebuild: {ArcadeDemoBloc.groupBanner},
      );
    }
  }
}

class _ReadEntryUseCase extends BlocUseCase<ArcadeDemoBloc, ReadEntryEvent> {
  @override
  Future<void> execute(ReadEntryEvent event) async {
    final entries = bloc.state.entries;
    final index = entries.indexWhere((e) => e.id == event.entryId);
    if (index == -1) return;

    final entry = entries[index];
    final now = bloc.state.now;

    emitUpdate(
      newState: bloc.state.copyWith(isOperationInProgress: true),
    );

    try {
      final storage = bloc.storageBloc;
      Object? value;

      switch (entry.backend) {
        case DemoBackend.prefs:
          value = await storage.prefsRead<String>(entry.key);
          break;
        case DemoBackend.hive:
          value = await storage.hiveRead<String>('arcade_box', entry.key);
          break;
        case DemoBackend.secure:
          value = await storage.secureRead(entry.key);
          break;
        case DemoBackend.sqlite:
          final rows = await storage.sqliteQuery(
            'SELECT v FROM kv WHERE k = ?',
            [entry.key],
          );
          value = rows.isEmpty ? null : rows.first['v'];
          break;
      }

      // Check if lazy eviction occurred
      final wasExpired = entry.ttl != null && entry.isExpired(now);
      final evicted = (value == null) &&
          wasExpired &&
          (entry.backend == DemoBackend.prefs ||
              entry.backend == DemoBackend.hive);

      String banner;
      List<DemoEntry> newEntries = bloc.state.entries;

      if (evicted) {
        banner = 'READ ${entry.backend.name}:${entry.key} '
            '→ null (EXPIRED → EVICTED)';
        // Remove from list
        newEntries = [...newEntries]..removeWhere((e) => e.id == event.entryId);
      } else {
        banner = 'READ ${entry.backend.name}:${entry.key} → ${value ?? "null"}';
      }

      emitUpdate(
        newState: bloc.state.copyWith(
          entries: newEntries,
          banner: banner,
          isOperationInProgress: false,
        ),
        groupsToRebuild: {ArcadeDemoBloc.groupEntries, ArcadeDemoBloc.groupBanner},
      );
    } catch (e) {
      emitUpdate(
        newState: bloc.state.copyWith(
          banner: 'READ ERROR: $e',
          isOperationInProgress: false,
        ),
        groupsToRebuild: {ArcadeDemoBloc.groupBanner},
      );
    }
  }
}

class _DeleteEntryUseCase extends BlocUseCase<ArcadeDemoBloc, DeleteEntryEvent> {
  @override
  Future<void> execute(DeleteEntryEvent event) async {
    final entries = bloc.state.entries;
    final index = entries.indexWhere((e) => e.id == event.entryId);
    if (index == -1) return;

    final entry = entries[index];

    emitUpdate(
      newState: bloc.state.copyWith(isOperationInProgress: true),
    );

    try {
      final storage = bloc.storageBloc;

      switch (entry.backend) {
        case DemoBackend.prefs:
          await storage.prefsDelete(entry.key);
          break;
        case DemoBackend.hive:
          await storage.hiveDelete('arcade_box', entry.key);
          break;
        case DemoBackend.secure:
          await storage.secureDelete(entry.key);
          break;
        case DemoBackend.sqlite:
          await storage.sqliteRaw('DELETE FROM kv WHERE k = ?', [entry.key]);
          break;
      }

      final newEntries = [...entries]..removeAt(index);

      emitUpdate(
        newState: bloc.state.copyWith(
          entries: newEntries,
          banner: 'DELETED ${entry.backend.name}:${entry.key}',
          isOperationInProgress: false,
        ),
        groupsToRebuild: {ArcadeDemoBloc.groupEntries, ArcadeDemoBloc.groupBanner},
      );
    } catch (e) {
      emitUpdate(
        newState: bloc.state.copyWith(
          banner: 'DELETE ERROR: $e',
          isOperationInProgress: false,
        ),
        groupsToRebuild: {ArcadeDemoBloc.groupBanner},
      );
    }
  }
}

class _SpawnBombsUseCase extends BlocUseCase<ArcadeDemoBloc, SpawnBombsEvent> {
  @override
  Future<void> execute(SpawnBombsEvent event) async {
    final rnd = Random();
    final backends = [DemoBackend.prefs, DemoBackend.hive];
    final storage = bloc.storageBloc;
    final newEntries = <DemoEntry>[];

    for (int i = 0; i < 3; i++) {
      final backend = backends[i % backends.length];
      final key = 'bomb${rnd.nextInt(999)}';
      final value = 'tick${rnd.nextInt(9999)}';
      final ttlSecs = [3, 5, 8][i];

      final entry = DemoEntry(
        backend: backend,
        key: key,
        value: value,
        createdAt: DateTime.now(),
        ttl: Duration(seconds: ttlSecs),
      );

      try {
        switch (backend) {
          case DemoBackend.prefs:
            await storage.prefsWrite(key, value, ttl: Duration(seconds: ttlSecs));
            break;
          case DemoBackend.hive:
            await storage.hiveWrite('arcade_box', key, value,
                ttl: Duration(seconds: ttlSecs));
            break;
          default:
            break;
        }
        newEntries.add(entry);
      } catch (_) {
        // Continue on error
      }
    }

    final allEntries = [...newEntries.reversed, ...bloc.state.entries];

    emitUpdate(
      newState: bloc.state.copyWith(
        entries: allEntries,
        banner: 'Spawned ${newEntries.length} time bombs!',
      ),
      groupsToRebuild: {ArcadeDemoBloc.groupEntries, ArcadeDemoBloc.groupBanner},
    );
  }
}

class _CleanupCacheUseCase
    extends BlocUseCase<ArcadeDemoBloc, CleanupCacheEvent> {
  @override
  Future<void> execute(CleanupCacheEvent event) async {
    emitUpdate(
      newState: bloc.state.copyWith(isOperationInProgress: true),
    );

    try {
      final storage = bloc.storageBloc;
      final cleaned = await storage.cleanupExpiredCache();

      // Remove expired entries from UI
      final now = bloc.state.now;
      final newEntries = bloc.state.entries
          .where((e) => e.ttl == null || !e.isExpired(now))
          .toList();

      emitUpdate(
        newState: bloc.state.copyWith(
          entries: newEntries,
          banner: 'CLEANUP: $cleaned entries removed',
          isOperationInProgress: false,
        ),
        groupsToRebuild: {ArcadeDemoBloc.groupEntries, ArcadeDemoBloc.groupBanner},
      );
    } catch (e) {
      emitUpdate(
        newState: bloc.state.copyWith(
          banner: 'CLEANUP ERROR: $e',
          isOperationInProgress: false,
        ),
        groupsToRebuild: {ArcadeDemoBloc.groupBanner},
      );
    }
  }
}
