import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:juice/juice.dart';
import 'package:juice_network/juice_network.dart';
import 'package:juice_storage/juice_storage.dart';
import 'package:mocktail/mocktail.dart';

class MockStorageBloc extends Mock implements StorageBloc {}

void main() {
  late FetchBloc fetchBloc;
  late Dio dio;
  late DioAdapter dioAdapter;
  late MockStorageBloc mockStorageBloc;

  setUp(() {
    dio = Dio();
    dioAdapter = DioAdapter(dio: dio);
    mockStorageBloc = MockStorageBloc();

    // Mock all storage operations
    when(() => mockStorageBloc.hiveOpenBox(any()))
        .thenAnswer((_) async {});
    when(() => mockStorageBloc.hiveWrite(any(), any(), any(), ttl: any(named: 'ttl')))
        .thenAnswer((_) async {});
    when(() => mockStorageBloc.hiveRead(any(), any()))
        .thenAnswer((_) async => null);
    when(() => mockStorageBloc.hiveDelete(any(), any()))
        .thenAnswer((_) async {});

    fetchBloc = FetchBloc(
      storageBloc: mockStorageBloc,
      dio: dio,
    );
  });

  tearDown(() async {
    await fetchBloc.close();
  });

  /// Helper to send event and wait for state update.
  Future<void> sendAndWaitForState(FetchBloc bloc, EventBase event) async {
    final completer = Completer<void>();
    late StreamSubscription<StreamStatus<FetchState>> sub;
    sub = bloc.stream.listen((status) {
      if (status is! WaitingStatus) {
        if (!completer.isCompleted) completer.complete();
        sub.cancel();
      }
    });
    // Errors from use cases are expected to be caught and emitted as FailureStatus
    // but they may still propagate from send(), so we catch them here.
    try {
      await bloc.send(event);
    } catch (_) {
      // Error will be reflected in state via FailureStatus
    }
    await completer.future.timeout(const Duration(seconds: 5));
  }

  group('FetchBloc', () {
    test('initial state is not initialized', () {
      expect(fetchBloc.state.isInitialized, isFalse);
      expect(fetchBloc.state.inflightCount, 0);
      expect(fetchBloc.state.activeRequests, isEmpty);
    });

    test('InitializeFetchEvent sets isInitialized to true', () async {
      await sendAndWaitForState(
        fetchBloc,
        InitializeFetchEvent(
          config: FetchConfig(baseUrl: 'https://api.example.com'),
        ),
      );

      expect(fetchBloc.state.isInitialized, isTrue);
      expect(fetchBloc.state.config.baseUrl, 'https://api.example.com');
    });

    test('GetEvent makes HTTP request and updates state', () async {
      dioAdapter.onGet(
        '/users/1',
        (server) => server.reply(200, {'id': 1, 'name': 'John'}),
      );

      await sendAndWaitForState(fetchBloc, InitializeFetchEvent());

      await sendAndWaitForState(
        fetchBloc,
        GetEvent(
          url: '/users/1',
          cachePolicy: CachePolicy.networkOnly,
        ),
      );

      expect(fetchBloc.state.inflightCount, 0);
      expect(fetchBloc.state.stats.successCount, 1);
    });

    test('GetEvent handles network error', () async {
      dioAdapter.onGet(
        '/users/1',
        (server) => server.reply(500, {'error': 'Internal Server Error'}),
      );

      await sendAndWaitForState(fetchBloc, InitializeFetchEvent());

      // Run in a guarded zone to capture async errors that escape
      await runZonedGuarded(() async {
        await sendAndWaitForState(
          fetchBloc,
          GetEvent(
            url: '/users/1',
            cachePolicy: CachePolicy.networkOnly,
          ),
        );
      }, (error, stack) {
        // Expected - DioException escapes even though we handle it
      });

      expect(fetchBloc.state.lastError, isA<ServerError>());
      expect(fetchBloc.state.stats.failureCount, 1);
    });

    test('PostEvent sends body', () async {
      dioAdapter.onPost(
        '/users',
        (server) => server.reply(201, {'id': 2, 'name': 'Jane'}),
        data: {'name': 'Jane'},
      );

      await sendAndWaitForState(fetchBloc, InitializeFetchEvent());

      await sendAndWaitForState(
        fetchBloc,
        PostEvent(
          url: '/users',
          body: {'name': 'Jane'},
        ),
      );

      expect(fetchBloc.state.stats.successCount, 1);
    });

    test('ResetFetchEvent clears state', () async {
      await sendAndWaitForState(fetchBloc, InitializeFetchEvent());
      await sendAndWaitForState(
        fetchBloc,
        ResetFetchEvent(
          cancelInflight: true,
          resetStats: true,
        ),
      );

      expect(fetchBloc.state.activeRequests, isEmpty);
      expect(fetchBloc.state.inflightCount, 0);
      expect(fetchBloc.state.stats.totalRequests, 0);
    });

    test('ResetStatsEvent resets statistics', () async {
      dioAdapter.onGet(
        '/test',
        (server) => server.reply(200, {}),
      );

      await sendAndWaitForState(fetchBloc, InitializeFetchEvent());
      await sendAndWaitForState(
        fetchBloc,
        GetEvent(
          url: '/test',
          cachePolicy: CachePolicy.networkOnly,
        ),
      );

      expect(fetchBloc.state.stats.successCount, 1);

      await sendAndWaitForState(fetchBloc, ResetStatsEvent());

      expect(fetchBloc.state.stats.successCount, 0);
      expect(fetchBloc.state.stats.totalRequests, 0);
    });

    test('ClearLastErrorEvent clears error', () async {
      dioAdapter.onGet(
        '/error',
        (server) => server.reply(500, {'error': 'Internal Server Error'}),
      );

      await sendAndWaitForState(fetchBloc, InitializeFetchEvent());

      // Run in a guarded zone to capture async errors that escape
      await runZonedGuarded(() async {
        await sendAndWaitForState(
          fetchBloc,
          GetEvent(
            url: '/error',
            cachePolicy: CachePolicy.networkOnly,
          ),
        );
      }, (error, stack) {
        // Expected - DioException escapes even though we handle it
      });

      expect(fetchBloc.state.lastError, isNotNull);

      await sendAndWaitForState(fetchBloc, ClearLastErrorEvent());

      expect(fetchBloc.state.lastError, isNull);
    });
  });

  group('Request coalescing', () {
    test('duplicate requests share same network call', () async {
      var callCount = 0;
      dioAdapter.onGet(
        '/shared',
        (server) {
          callCount++;
          return server.reply(200, {'count': callCount});
        },
      );

      await sendAndWaitForState(fetchBloc, InitializeFetchEvent());

      // Send multiple requests simultaneously
      final futures = [
        sendAndWaitForState(
          fetchBloc,
          GetEvent(url: '/shared', cachePolicy: CachePolicy.networkOnly),
        ),
        sendAndWaitForState(
          fetchBloc,
          GetEvent(url: '/shared', cachePolicy: CachePolicy.networkOnly),
        ),
        sendAndWaitForState(
          fetchBloc,
          GetEvent(url: '/shared', cachePolicy: CachePolicy.networkOnly),
        ),
      ];

      await Future.wait(futures);

      // Only one network call should have been made
      expect(callCount, 1);
      expect(fetchBloc.state.stats.coalescedCount, greaterThanOrEqualTo(2));
    });
  });

  group('Decode function', () {
    test('decode function transforms response', () async {
      dioAdapter.onGet(
        '/users/1',
        (server) => server.reply(200, {'id': 1, 'name': 'John'}),
      );

      await sendAndWaitForState(fetchBloc, InitializeFetchEvent());

      String? decodedName;
      await sendAndWaitForState(
        fetchBloc,
        GetEvent(
          url: '/users/1',
          cachePolicy: CachePolicy.networkOnly,
          decode: (raw) {
            decodedName = raw['name'] as String;
            return raw;
          },
        ),
      );

      expect(decodedName, 'John');
    });
  });
}
