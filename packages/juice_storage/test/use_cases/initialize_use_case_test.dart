import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:juice/juice.dart';
import 'package:juice_storage/src/adapters/hive_gateway.dart';
import 'package:juice_storage/src/cache/cache_index.dart';
import 'package:juice_storage/src/cache/cache_metadata.dart';
import 'package:juice_storage/src/storage_bloc.dart';
import 'package:juice_storage/src/storage_config.dart';
import 'package:juice_storage/src/storage_state.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// THE RETRY PINS (2026-09-01, the stale-lock cold boot): a killed
/// process's leftover box lock fails exactly one boot; the hive leg must
/// retry ONCE and heal — and a persistent failure must be LOUD (logged
/// and in state), never a silently dead cache. These exist because the
/// fix first shipped unpinned behind an "honest note", which is a
/// shortcut by another name.
class _FlakyGateway implements HiveGateway {
  _FlakyGateway({this.failuresBeforeSuccess = 1});
  final int failuresBeforeSuccess;
  int initCalls = 0;
  int boxesOpened = 0;

  @override
  Future<void> init(String? path) async {
    initCalls++;
    if (initCalls <= failuresBeforeSuccess) {
      throw FileSystemException('lock failed', '$path/box.lock');
    }
  }

  @override
  bool isAdapterRegistered(int typeId) => true;

  @override
  void registerAdapter(TypeAdapter<dynamic> adapter) {}

  @override
  Future<int> openBox(String name) async {
    boxesOpened++;
    return 0;
  }
}

class _RecordingLogger implements JuiceLogger {
  final logs = <String>[];
  final errors = <String>[];

  @override
  void log(String message,
          {Level level = Level.info, Map<String, dynamic>? context}) =>
      logs.add(message);

  @override
  void logError(String message, Object error, StackTrace stackTrace,
          {Map<String, dynamic>? context}) =>
      errors.add(message);
}

void main() {
  late Directory tempDir;
  late _RecordingLogger logger;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('init_use_case_test_');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(900)) {
      Hive.registerAdapter(CacheMetadataAdapter());
    }
  });

  tearDownAll(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  setUp(() {
    logger = _RecordingLogger();
    JuiceLoggerConfig.configureLogger(logger);
  });

  StorageBloc bloc(HiveGateway gateway) => StorageBloc(
        config: const StorageConfig(hiveBoxesToOpen: ['pins']),
        cacheIndex: CacheIndex(),
        hiveGateway: gateway,
      );

  test('a clean init readies hive first try — no retry, no noise', () async {
    final gw = _FlakyGateway(failuresBeforeSuccess: 0);
    final b = bloc(gw);
    await b.initialize();
    expect(b.state.backendStatus.hive, BackendState.ready);
    expect(gw.initCalls, 1);
    expect(logger.errors, isEmpty);
    await b.close();
  });

  test('THE STALE-LOCK CLASS: one transient failure heals on the single '
      'retry — hive ready, boxes open, retry noted in the log', () async {
    final gw = _FlakyGateway(failuresBeforeSuccess: 1);
    final b = bloc(gw);
    await b.initialize();
    expect(b.state.backendStatus.hive, BackendState.ready,
        reason: 'the retry healed the boot');
    expect(gw.initCalls, 2, reason: 'exactly one retry');
    expect(gw.boxesOpened, 1);
    expect(logger.logs.any((m) => m.contains('retrying once')), isTrue,
        reason: 'the transient is noted, not silent');
    expect(logger.errors, isEmpty, reason: 'a healed boot is not an error');
    await b.close();
  });

  test('a PERSISTENT failure is loud: error state, StorageError, and a '
      'logged error — never a silently dead cache', () async {
    final gw = _FlakyGateway(failuresBeforeSuccess: 99);
    final b = bloc(gw);
    await b.initialize();
    expect(b.state.backendStatus.hive, BackendState.error);
    expect(gw.initCalls, 2, reason: 'bounded — one retry, not a spin');
    expect(b.state.lastError?.message, contains('Hive initialization failed'));
    expect(logger.errors.any((m) => m.contains('DEAD this session')), isTrue,
        reason: 'the pulled log must say WHY prefs are dead');
    await b.close();
  });
}
