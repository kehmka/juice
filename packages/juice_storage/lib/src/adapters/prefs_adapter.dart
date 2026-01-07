import 'package:shared_preferences/shared_preferences.dart';

import 'key_value_adapter.dart';

/// SharedPreferences implementation of [KeyValueAdapter].
///
/// Handles key prefixing internally. Callers always use logical keys;
/// the adapter applies the configured prefix.
///
/// Supports: String, int, double, bool, List<String>
class PrefsAdapter implements KeyValueAdapter<Object> {
  PrefsAdapter({
    required SharedPreferences prefs,
    required String keyPrefix,
  })  : _prefs = prefs,
        _keyPrefix = keyPrefix;

  final SharedPreferences _prefs;
  final String _keyPrefix;

  /// The key prefix used by this adapter.
  String get keyPrefix => _keyPrefix;

  /// Convert a logical key to a prefixed key.
  String _prefixedKey(String key) => '$_keyPrefix$key';

  /// Check if a prefixed key belongs to this adapter.
  bool _isOurKey(String prefixedKey) => prefixedKey.startsWith(_keyPrefix);

  /// Extract the logical key from a prefixed key.
  String _logicalKey(String prefixedKey) =>
      prefixedKey.substring(_keyPrefix.length);

  @override
  Future<Object?> read(String key) async {
    return _prefs.get(_prefixedKey(key));
  }

  @override
  Future<void> write(String key, Object value) async {
    final prefixedKey = _prefixedKey(key);

    switch (value) {
      case String s:
        await _prefs.setString(prefixedKey, s);
      case int i:
        await _prefs.setInt(prefixedKey, i);
      case double d:
        await _prefs.setDouble(prefixedKey, d);
      case bool b:
        await _prefs.setBool(prefixedKey, b);
      case List<String> l:
        await _prefs.setStringList(prefixedKey, l);
      default:
        throw ArgumentError(
          'SharedPreferences does not support type ${value.runtimeType}. '
          'Supported types: String, int, double, bool, List<String>',
        );
    }
  }

  @override
  Future<void> delete(String key) async {
    await _prefs.remove(_prefixedKey(key));
  }

  @override
  Future<void> clear() async {
    // Only clear keys that belong to this adapter (have our prefix)
    final keysToRemove = _prefs.getKeys().where(_isOurKey).toList();
    for (final key in keysToRemove) {
      await _prefs.remove(key);
    }
  }

  @override
  Future<bool> containsKey(String key) async {
    return _prefs.containsKey(_prefixedKey(key));
  }

  @override
  Future<Iterable<String>> keys() async {
    // Return logical keys (without prefix) for keys that belong to us
    return _prefs.getKeys().where(_isOurKey).map(_logicalKey);
  }

  /// Reload preferences from disk.
  Future<void> reload() async {
    await _prefs.reload();
  }
}

/// Factory for creating SharedPreferences adapter.
class PrefsAdapterFactory {
  PrefsAdapterFactory._();

  static PrefsAdapter? _adapter;

  /// Initialize and get the adapter.
  ///
  /// If [prefs] is provided, uses that instance. Otherwise, gets the
  /// singleton SharedPreferences instance.
  static PrefsAdapter init({
    SharedPreferences? prefs,
    required String keyPrefix,
  }) {
    if (_adapter != null) {
      return _adapter!;
    }

    if (prefs == null) {
      throw StateError(
        'SharedPreferences instance must be provided. '
        'Call SharedPreferences.getInstance() first.',
      );
    }

    _adapter = PrefsAdapter(prefs: prefs, keyPrefix: keyPrefix);
    return _adapter!;
  }

  /// Get the existing adapter.
  ///
  /// Returns null if not initialized.
  static PrefsAdapter? get instance => _adapter;

  /// Clear the adapter (for testing).
  static void reset() {
    _adapter = null;
  }
}
