import 'package:hive/hive.dart';

import 'key_value_adapter.dart';

/// Hive implementation of [KeyValueAdapter].
///
/// Wraps a Hive [Box] to provide consistent key-value operations.
/// Supports both regular and lazy boxes.
class HiveAdapter<T> implements KeyValueAdapter<T> {
  HiveAdapter(this._box);

  final BoxBase<T> _box;

  /// The underlying Hive box.
  BoxBase<T> get box => _box;

  /// The name of this box.
  String get boxName => _box.name;

  /// Whether this is a lazy box.
  bool get isLazy => _box is LazyBox<T>;

  @override
  Future<T?> read(String key) async {
    final box = _box;
    if (box is LazyBox<T>) {
      return box.get(key);
    }
    return (box as Box<T>).get(key);
  }

  @override
  Future<void> write(String key, T value) async {
    await _box.put(key, value);
  }

  @override
  Future<void> delete(String key) async {
    await _box.delete(key);
  }

  @override
  Future<void> clear() async {
    await _box.clear();
  }

  @override
  Future<bool> containsKey(String key) async {
    return _box.containsKey(key);
  }

  @override
  Future<Iterable<String>> keys() async {
    return _box.keys.cast<String>();
  }

  /// Get the number of entries in this box.
  int get length => _box.length;

  /// Close this box.
  Future<void> close() async {
    await _box.close();
  }

  /// Whether this box is open.
  bool get isOpen => _box.isOpen;
}

/// Factory for creating and managing Hive adapters.
class HiveAdapterFactory {
  HiveAdapterFactory._();

  static final Map<String, HiveAdapter<dynamic>> _adapters = {};

  /// Open a box and create an adapter for it.
  static Future<HiveAdapter<T>> open<T>(
    String boxName, {
    bool lazy = false,
  }) async {
    if (_adapters.containsKey(boxName)) {
      return _adapters[boxName]! as HiveAdapter<T>;
    }

    final BoxBase<T> box;
    if (lazy) {
      box = await Hive.openLazyBox<T>(boxName);
    } else {
      box = await Hive.openBox<T>(boxName);
    }

    final adapter = HiveAdapter<T>(box);
    _adapters[boxName] = adapter;
    return adapter;
  }

  /// Get an existing adapter by box name.
  static HiveAdapter<T>? get<T>(String boxName) {
    return _adapters[boxName] as HiveAdapter<T>?;
  }

  /// Close a box and remove its adapter.
  static Future<void> close(String boxName) async {
    final adapter = _adapters.remove(boxName);
    if (adapter != null) {
      await adapter.close();
    }
  }

  /// Close all boxes.
  static Future<void> closeAll() async {
    for (final adapter in _adapters.values) {
      await adapter.close();
    }
    _adapters.clear();
  }

  /// Get all open box names.
  static Iterable<String> get openBoxes => _adapters.keys;

  /// Reset the factory for testing purposes.
  ///
  /// This clears the adapter map without closing boxes.
  /// Only use this in test setup/teardown.
  static void resetForTesting() {
    _adapters.clear();
  }
}
