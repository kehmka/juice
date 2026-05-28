import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:juice/juice.dart';
import 'package:juice_network/juice_network.dart';

import 'support/cache_test_support.dart';

/// Verifies the cache-safety rules in `_cacheResponse`: authorized responses,
/// sensitive endpoints, and `Cache-Control: no-store` are not cached unless
/// explicitly opted in.
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
    } catch (_) {}
    await completer.future.timeout(const Duration(seconds: 5));
  }

  void onGet(
    String path,
    Object body, {
    Map<String, List<String>>? headers,
  }) {
    dioAdapter.onGet(
      path,
      (server) => server.reply(
        200,
        body,
        headers: {
          'content-type': ['application/json'],
          ...?headers,
        },
      ),
    );
  }

  /// Whether anything was written to the cache for [url].
  Future<bool> isCached(String url, {Map<String, String>? authScopeHeaders}) async {
    final key = RequestKey.from(
      method: 'GET',
      url: url,
      // Auth requests carry an authScope derived from the Authorization header.
      authScope: authScopeHeaders?['Authorization']?.startsWith('Bearer ') ?? false
          ? 'bearer'
          : null,
    );
    final record = await fetchBloc.cacheManager.get(key);
    return record != null;
  }

  group('Authorization', () {
    test('authorized response is NOT cached by default', () async {
      onGet('/profile', {'id': 1});
      await sendAndSettle(InitializeFetchEvent());

      const auth = {'Authorization': 'Bearer token'};
      await sendAndSettle(GetEvent(
        url: '/profile',
        cachePolicy: CachePolicy.cacheFirst,
        ttl: const Duration(minutes: 5),
        headers: auth,
      ));

      expect(await isCached('/profile', authScopeHeaders: auth), isFalse);
    });

    test('authorized response IS cached when cacheAuthResponses: true',
        () async {
      onGet('/profile', {'id': 1});
      await sendAndSettle(InitializeFetchEvent());

      const auth = {'Authorization': 'Bearer token'};
      await sendAndSettle(GetEvent(
        url: '/profile',
        cachePolicy: CachePolicy.cacheFirst,
        ttl: const Duration(minutes: 5),
        headers: auth,
        cacheAuthResponses: true,
      ));

      expect(await isCached('/profile', authScopeHeaders: auth), isTrue);
    });
  });

  group('Sensitive endpoints', () {
    test('/auth/* responses are never cached', () async {
      onGet('/auth/login', {'token': 'x'});
      await sendAndSettle(InitializeFetchEvent());

      await sendAndSettle(GetEvent(
        url: '/auth/login',
        cachePolicy: CachePolicy.cacheFirst,
        ttl: const Duration(minutes: 5),
      ));

      expect(await isCached('/auth/login'), isFalse);
    });

    test('forceCache overrides sensitive-endpoint protection', () async {
      onGet('/auth/login', {'token': 'x'});
      await sendAndSettle(InitializeFetchEvent());

      await sendAndSettle(GetEvent(
        url: '/auth/login',
        cachePolicy: CachePolicy.cacheFirst,
        ttl: const Duration(minutes: 5),
        forceCache: true,
      ));

      expect(await isCached('/auth/login'), isTrue);
    });
  });

  group('Cache-Control', () {
    test('no-store response is not cached', () async {
      onGet('/data', {'v': 1}, headers: {
        'cache-control': ['no-store'],
      });
      await sendAndSettle(InitializeFetchEvent());

      await sendAndSettle(GetEvent(
        url: '/data',
        cachePolicy: CachePolicy.cacheFirst,
        ttl: const Duration(minutes: 5),
      ));

      expect(await isCached('/data'), isFalse);
    });

    test('forceCache overrides no-store', () async {
      onGet('/data', {'v': 1}, headers: {
        'cache-control': ['no-store'],
      });
      await sendAndSettle(InitializeFetchEvent());

      await sendAndSettle(GetEvent(
        url: '/data',
        cachePolicy: CachePolicy.cacheFirst,
        ttl: const Duration(minutes: 5),
        forceCache: true,
      ));

      expect(await isCached('/data'), isTrue);
    });
  });
}
