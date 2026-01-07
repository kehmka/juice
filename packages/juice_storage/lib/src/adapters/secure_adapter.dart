import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'key_value_adapter.dart';

/// FlutterSecureStorage implementation of [KeyValueAdapter].
///
/// Stores encrypted values. Only supports String values.
/// TTL is NOT supported for secure storage - secrets require explicit deletion.
class SecureAdapter implements KeyValueAdapter<String> {
  SecureAdapter({
    required FlutterSecureStorage storage,
  }) : _storage = storage;

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) async {
    return _storage.read(key: key);
  }

  @override
  Future<void> write(String key, String value) async {
    await _storage.write(key: key, value: value);
  }

  @override
  Future<void> delete(String key) async {
    await _storage.delete(key: key);
  }

  @override
  Future<void> clear() async {
    await _storage.deleteAll();
  }

  @override
  Future<bool> containsKey(String key) async {
    return _storage.containsKey(key: key);
  }

  @override
  Future<Iterable<String>> keys() async {
    final all = await _storage.readAll();
    return all.keys;
  }
}

/// Factory for creating SecureStorage adapter.
class SecureAdapterFactory {
  SecureAdapterFactory._();

  static SecureAdapter? _adapter;

  /// Initialize and get the adapter.
  ///
  /// [iOSOptions] and [androidOptions] configure platform-specific behavior.
  static SecureAdapter init({
    IOSOptions? iOSOptions,
    AndroidOptions? androidOptions,
  }) {
    if (_adapter != null) {
      return _adapter!;
    }

    final storage = FlutterSecureStorage(
      iOptions: iOSOptions ?? IOSOptions.defaultOptions,
      aOptions: androidOptions ?? AndroidOptions.defaultOptions,
    );

    _adapter = SecureAdapter(storage: storage);
    return _adapter!;
  }

  /// Get the existing adapter.
  ///
  /// Returns null if not initialized.
  static SecureAdapter? get instance => _adapter;

  /// Check if secure storage is available on this platform.
  ///
  /// Returns false on platforms that don't support secure storage.
  static Future<bool> isAvailable() async {
    try {
      const storage = FlutterSecureStorage();
      // Try a test operation
      await storage.write(key: '__test__', value: 'test');
      await storage.delete(key: '__test__');
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Clear the adapter (for testing).
  static void reset() {
    _adapter = null;
  }
}
