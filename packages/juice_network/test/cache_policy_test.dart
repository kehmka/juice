import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:juice/juice.dart';
import 'package:juice_network/juice_network.dart';

import 'support/cache_test_support.dart';

void main() {
  late FetchBloc fetchBloc;
  late Dio dio;
  late DioAdapter dioAdapter;
  late MockStorageBloc storageBloc;

  setUp(() {
    dio = Dio();
    dioAdapter = DioAdapter(dio: dio);
    storageBloc = createStatefulStorageBloc();
    fetchBloc = FetchBloc(storageBloc: storageBloc, dio: dio);
  });

  tearDown(() async {
    await fetchBloc.close();
  });

  /// Send an event and wait until the bloc emits a non-waiting status.
  ///
  /// Network-call counts are asserted via [FetchState.stats] (successCount,
  /// cacheHits, cacheMisses) rather than the mock handler, because
  /// http_mock_adapter invokes the handler at registration time, not per call.
  Future<void> sendAndSettle(EventBase event) async {
    final completer = Completer<void>();
    late StreamSubscription<StreamStatus<FetchState>> sub;
    sub = fetchBloc.stream.listen((status) {
      if (status is! WaitingStatus) {
        if (!completer.isCompleted) completer.complete();
        sub.cancel();
      }
    });
    try {
      await fetchBloc.send(event);
    } catch (_) {
      // Errors surface via FailureStatus / state.lastError.
    }
    await completer.future.timeout(const Duration(seconds: 5));
  }

  /// Register a JSON GET reply with a JSON content-type so cached records
  /// decode back to maps.
  void onGetJson(String path, Object body, {int status = 200}) {
    dioAdapter.onGet(
      path,
      (server) => server.reply(
        status,
        body,
        headers: {
          'content-type': ['application/json'],
        },
      ),
    );
  }

  WireCacheRecord record(
    String url,
    String json, {
    required Duration expiresIn,
  }) {
    final key = RequestKey.from(method: 'GET', url: url);
    return WireCacheRecord(
      canonicalKey: key.canonical,
      bodyBytes: Uint8List.fromList(json.codeUnits),
      statusCode: 200,
      headers: const {'content-type': 'application/json'},
      cachedAt: DateTime.now(),
      expiresAt: DateTime.now().add(expiresIn),
    );
  }

  group('CachePolicy.networkOnly', () {
    test('always hits network and never writes cache', () async {
      onGetJson('/data', {'v': 1});
      await sendAndSettle(InitializeFetchEvent());

      await sendAndSettle(
        GetEvent(url: '/data', cachePolicy: CachePolicy.networkOnly),
      );
      await sendAndSettle(
        GetEvent(url: '/data', cachePolicy: CachePolicy.networkOnly),
      );

      expect(fetchBloc.state.stats.successCount, 2);
      expect(fetchBloc.state.stats.cacheHits, 0);
      final cached = await fetchBloc.cacheManager
          .get(RequestKey.from(method: 'GET', url: '/data'));
      expect(cached, isNull);
    });
  });

  group('CachePolicy.cacheFirst', () {
    test('miss fetches and caches; second call is a cache hit (no network)',
        () async {
      onGetJson('/data', {'v': 1});
      await sendAndSettle(InitializeFetchEvent());

      await sendAndSettle(GetEvent(
        url: '/data',
        cachePolicy: CachePolicy.cacheFirst,
        ttl: const Duration(minutes: 5),
      ));
      expect(fetchBloc.state.stats.cacheMisses, 1);
      expect(fetchBloc.state.stats.successCount, 1);

      await sendAndSettle(GetEvent(
        url: '/data',
        cachePolicy: CachePolicy.cacheFirst,
        ttl: const Duration(minutes: 5),
      ));

      // Second call served from cache: a hit, and no new network success.
      expect(fetchBloc.state.stats.cacheHits, 1);
      expect(fetchBloc.state.stats.successCount, 1);
    });

    test('expired entry is ignored and refetched', () async {
      onGetJson('/data', {'v': 'fresh'});
      await sendAndSettle(InitializeFetchEvent());

      await fetchBloc.cacheManager.put(
        RequestKey.from(method: 'GET', url: '/data'),
        record('/data', '{"v":"stale"}', expiresIn: const Duration(hours: -1)),
      );

      await sendAndSettle(GetEvent(
        url: '/data',
        cachePolicy: CachePolicy.cacheFirst,
        ttl: const Duration(minutes: 5),
      ));

      // Expired entry → treated as a miss → network refetch.
      expect(fetchBloc.state.stats.cacheMisses, 1);
      expect(fetchBloc.state.stats.successCount, 1);
    });
  });

  group('CachePolicy.cacheOnly', () {
    test('miss fails without hitting the network', () async {
      onGetJson('/data', {'v': 1});
      await sendAndSettle(InitializeFetchEvent());

      await sendAndSettle(
        GetEvent(url: '/data', cachePolicy: CachePolicy.cacheOnly),
      );

      expect(fetchBloc.state.stats.successCount, 0);
      expect(fetchBloc.state.lastError, isA<CancelledError>());
    });

    test('hit returns cached data without network', () async {
      onGetJson('/data', {'v': 1});
      await sendAndSettle(InitializeFetchEvent());

      await fetchBloc.cacheManager.put(
        RequestKey.from(method: 'GET', url: '/data'),
        record('/data', '{"v":1}', expiresIn: const Duration(hours: 1)),
      );

      await sendAndSettle(
        GetEvent(url: '/data', cachePolicy: CachePolicy.cacheOnly),
      );

      expect(fetchBloc.state.stats.cacheHits, 1);
      expect(fetchBloc.state.stats.successCount, 0);
    });
  });

  group('CachePolicy.networkFirst', () {
    test('fetches network even when a valid cache entry exists', () async {
      onGetJson('/data', {'v': 'network'});
      await sendAndSettle(InitializeFetchEvent());

      await fetchBloc.cacheManager.put(
        RequestKey.from(method: 'GET', url: '/data'),
        record('/data', '{"v":"cache"}', expiresIn: const Duration(hours: 1)),
      );

      await sendAndSettle(
        GetEvent(url: '/data', cachePolicy: CachePolicy.networkFirst),
      );

      // networkFirst does not check cache up front — it fetched.
      expect(fetchBloc.state.stats.successCount, 1);
      expect(fetchBloc.state.stats.cacheHits, 0);
    });

    test('falls back to stale cache on network failure', () async {
      dioAdapter.onGet('/data', (server) => server.reply(500, {'e': 'boom'}));
      await sendAndSettle(InitializeFetchEvent());

      await fetchBloc.cacheManager.put(
        RequestKey.from(method: 'GET', url: '/data'),
        record('/data', '{"v":"stale"}', expiresIn: const Duration(hours: -1)),
      );

      await sendAndSettle(GetEvent(
        url: '/data',
        cachePolicy: CachePolicy.networkFirst,
        retryable: false, // skip retry backoff in the test
      ));

      // Network failed, stale cache served the result — no surfaced error.
      expect(fetchBloc.state.lastError, isNull);
    });
  });

  group('CachePolicy.staleWhileRevalidate', () {
    test('serves stale immediately and refreshes in background', () async {
      onGetJson('/data', {'v': 'fresh'});
      await sendAndSettle(InitializeFetchEvent());

      final key = RequestKey.from(method: 'GET', url: '/data');
      await fetchBloc.cacheManager.put(
        key,
        record('/data', '{"v":"stale"}', expiresIn: const Duration(hours: -1)),
      );

      await sendAndSettle(GetEvent(
        url: '/data',
        cachePolicy: CachePolicy.staleWhileRevalidate,
        ttl: const Duration(minutes: 5),
      ));

      // Served from stale cache immediately.
      expect(fetchBloc.state.stats.cacheHits, 1);

      // Background refresh updates the cache with fresh data shortly after.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final refreshed = await fetchBloc.cacheManager.getStale(key);
      expect(refreshed!.bodyString, contains('fresh'));
    });
  });
}
