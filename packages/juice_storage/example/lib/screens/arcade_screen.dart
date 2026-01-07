import 'dart:math';

import 'package:juice/juice.dart';
import 'package:juice_storage/juice_storage.dart';

import '../demo_entry.dart';
import '../widgets/capsule_card.dart';

/// Main screen for the Storage Arcade demo.
///
/// Demonstrates:
/// - Saving values with TTL countdown
/// - Lazy eviction on read (expired items vanish)
/// - Manual cache cleanup
/// - Multiple storage backends
class ArcadeScreen extends StatefulWidget {
  const ArcadeScreen({super.key});

  @override
  State<ArcadeScreen> createState() => _ArcadeScreenState();
}

class _ArcadeScreenState extends State<ArcadeScreen> {
  final _listKey = GlobalKey<AnimatedListState>();
  final List<DemoEntry> _entries = [];
  Timer? _tick;

  // Input state
  DemoBackend _backend = DemoBackend.prefs;
  final _keyCtrl = TextEditingController(text: 'myKey');
  final _valCtrl = TextEditingController(text: '{"data": "hello"}');
  double _ttlSeconds = 10;

  // Banner message
  String _banner = 'Save an entry to get started';

  // Current time for countdown
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    // Tick every second for countdown display
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _keyCtrl.dispose();
    _valCtrl.dispose();
    super.dispose();
  }

  void _insertEntry(DemoEntry entry) {
    _entries.insert(0, entry);
    _listKey.currentState?.insertItem(
      0,
      duration: const Duration(milliseconds: 300),
    );
  }

  void _removeEntryAt(int index) {
    final removed = _entries.removeAt(index);
    _listKey.currentState?.removeItem(
      index,
      (context, animation) => SizeTransition(
        sizeFactor: animation,
        child: FadeTransition(
          opacity: animation,
          child: CapsuleCard(entry: removed, now: _now),
        ),
      ),
      duration: const Duration(milliseconds: 300),
    );
  }

  Future<void> _save(StorageBloc storage) async {
    final key = _keyCtrl.text.trim();
    if (key.isEmpty) {
      setState(() => _banner = 'Key cannot be empty');
      return;
    }

    final value = _valCtrl.text;
    final ttl = _ttlSeconds <= 0 ? null : Duration(seconds: _ttlSeconds.round());

    final entry = DemoEntry(
      backend: _backend,
      key: key,
      value: value,
      createdAt: DateTime.now(),
      ttl: ttl,
    );

    try {
      switch (_backend) {
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
          // Create table if needed, then insert
          await storage.sqliteRaw(
            'CREATE TABLE IF NOT EXISTS kv (k TEXT PRIMARY KEY, v TEXT)',
          );
          await storage.sqliteRaw(
            'INSERT OR REPLACE INTO kv(k,v) VALUES(?,?)',
            [key, value],
          );
          break;
      }

      _insertEntry(entry);
      setState(() {
        _banner = 'SAVED ${_backend.name}:$key'
            '${ttl != null ? " (TTL: ${ttl.inSeconds}s)" : " (no TTL)"}';
      });
    } catch (e) {
      setState(() => _banner = 'ERROR: $e');
    }
  }

  Future<void> _read(StorageBloc storage, DemoEntry entry, int index) async {
    Object? value;

    try {
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

      // Check if lazy eviction occurred (expired + null)
      final wasExpired = entry.ttl != null && entry.isExpired(_now);
      final evicted = (value == null) &&
          wasExpired &&
          (entry.backend == DemoBackend.prefs ||
              entry.backend == DemoBackend.hive);

      setState(() {
        if (evicted) {
          _banner = 'READ ${entry.backend.name}:${entry.key} '
              '→ null (EXPIRED → EVICTED)';
        } else {
          _banner = 'READ ${entry.backend.name}:${entry.key} → ${value ?? "null"}';
        }
      });

      // Animate removal if lazy eviction happened
      if (evicted) {
        _removeEntryAt(index);
      }
    } catch (e) {
      setState(() => _banner = 'READ ERROR: $e');
    }
  }

  Future<void> _delete(StorageBloc storage, DemoEntry entry, int index) async {
    try {
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

      _removeEntryAt(index);
      setState(() => _banner = 'DELETED ${entry.backend.name}:${entry.key}');
    } catch (e) {
      setState(() => _banner = 'DELETE ERROR: $e');
    }
  }

  Future<void> _cleanupNow(StorageBloc storage) async {
    try {
      final cleaned = await storage.cleanupExpiredCache();
      setState(() => _banner = 'CLEANUP: $cleaned entries removed');

      // Remove entries from UI that are now expired
      // (The backend already deleted them, update our list)
      final toRemove = <int>[];
      for (var i = 0; i < _entries.length; i++) {
        final entry = _entries[i];
        if (entry.ttl != null && entry.isExpired(_now)) {
          toRemove.add(i);
        }
      }
      // Remove in reverse to maintain indices
      for (final i in toRemove.reversed) {
        _removeEntryAt(i);
      }
    } catch (e) {
      setState(() => _banner = 'CLEANUP ERROR: $e');
    }
  }

  Future<void> _spawnBombs(StorageBloc storage) async {
    final rnd = Random();
    final backends = [DemoBackend.prefs, DemoBackend.hive];

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
        _insertEntry(entry);
      } catch (e) {
        // Continue on error
      }
    }

    setState(() => _banner = 'Spawned 3 time bombs!');
  }

  @override
  Widget build(BuildContext context) {
    return JuiceBuilder<StorageBloc>(
      groups: const {
        'storage:init',
        'storage:cache',
        'storage:prefs',
        'storage:hive:arcade_box',
        '*',
      },
      builder: (context, storage, status) {
        final isReady = storage.state.isInitialized;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Storage Arcade'),
            actions: [
              IconButton(
                tooltip: 'Spawn 3 time bombs',
                onPressed: isReady ? () => _spawnBombs(storage) : null,
                icon: const Icon(Icons.casino),
              ),
              IconButton(
                tooltip: 'Run cache cleanup now',
                onPressed: isReady ? () => _cleanupNow(storage) : null,
                icon: const Icon(Icons.cleaning_services),
              ),
            ],
          ),
          body: Column(
            children: [
              // Composer card
              _Composer(
                backend: _backend,
                onBackendChanged: (b) => setState(() => _backend = b),
                keyCtrl: _keyCtrl,
                valCtrl: _valCtrl,
                ttlSeconds: _ttlSeconds,
                onTtlChanged: (v) => setState(() => _ttlSeconds = v),
                onSave: isReady ? () => _save(storage) : null,
              ),

              // Banner
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Container(
                    key: ValueKey(_banner),
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.terminal, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _banner,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Entry list
              Expanded(
                child: AnimatedList(
                  key: _listKey,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  initialItemCount: _entries.length,
                  itemBuilder: (context, index, animation) {
                    final entry = _entries[index];
                    return SizeTransition(
                      sizeFactor: animation,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: CapsuleCard(
                          entry: entry,
                          now: _now,
                          onRead: () => _read(storage, entry, index),
                          onDelete: () => _delete(storage, entry, index),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Composer widget for creating new storage entries.
class _Composer extends StatelessWidget {
  const _Composer({
    required this.backend,
    required this.onBackendChanged,
    required this.keyCtrl,
    required this.valCtrl,
    required this.ttlSeconds,
    required this.onTtlChanged,
    required this.onSave,
  });

  final DemoBackend backend;
  final ValueChanged<DemoBackend> onBackendChanged;
  final TextEditingController keyCtrl;
  final TextEditingController valCtrl;
  final double ttlSeconds;
  final ValueChanged<double> onTtlChanged;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    // TTL only supported for prefs and hive
    final ttlSupported =
        backend == DemoBackend.prefs || backend == DemoBackend.hive;

    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                DropdownButton<DemoBackend>(
                  value: backend,
                  onChanged: (v) => v == null ? null : onBackendChanged(v),
                  items: DemoBackend.values
                      .map((b) => DropdownMenuItem(
                            value: b,
                            child: Text(b.name.toUpperCase()),
                          ))
                      .toList(),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: keyCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Key',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: onSave,
                  icon: const Icon(Icons.save, size: 18),
                  label: const Text('Save'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: valCtrl,
              decoration: const InputDecoration(
                labelText: 'Value',
                isDense: true,
              ),
              maxLines: 1,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  'TTL',
                  style: TextStyle(
                    color: ttlSupported ? null : Theme.of(context).disabledColor,
                  ),
                ),
                Expanded(
                  child: Slider(
                    value: ttlSeconds.clamp(0, 60),
                    min: 0,
                    max: 60,
                    divisions: 60,
                    label: ttlSeconds.round() == 0
                        ? 'None'
                        : '${ttlSeconds.round()}s',
                    onChanged: ttlSupported ? onTtlChanged : null,
                  ),
                ),
                SizedBox(
                  width: 48,
                  child: Text(
                    ttlSeconds.round() == 0 ? 'None' : '${ttlSeconds.round()}s',
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      color:
                          ttlSupported ? null : Theme.of(context).disabledColor,
                    ),
                  ),
                ),
              ],
            ),
            if (!ttlSupported)
              Text(
                backend == DemoBackend.secure
                    ? 'Secure storage: TTL not supported (by design)'
                    : 'SQLite: TTL not supported in this demo',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
              ),
          ],
        ),
      ),
    );
  }
}
