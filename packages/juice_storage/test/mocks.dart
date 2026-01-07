import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

// Hive mocks
class MockBox<T> extends Mock implements Box<T> {}

class MockLazyBox<T> extends Mock implements LazyBox<T> {}

// SharedPreferences mock
class MockSharedPreferences extends Mock implements SharedPreferences {}

// FlutterSecureStorage mock
class MockFlutterSecureStorage extends Mock implements FlutterSecureStorage {}

// SQLite mocks
class MockDatabase extends Mock implements Database {}

// Fallback values for mocktail
class FakeIOSOptions extends Fake implements IOSOptions {}

class FakeAndroidOptions extends Fake implements AndroidOptions {}

void registerFallbackValues() {
  registerFallbackValue(FakeIOSOptions());
  registerFallbackValue(FakeAndroidOptions());
}
