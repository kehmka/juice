import 'dart:math';

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

  Future<void> settle(EventBase event) async {
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

  /// Poll until [cond] is true (or timeout).
  Future<void> pumpUntil(bool Function() cond) async {
    final sw = Stopwatch()..start();
    while (!cond()) {
      if (sw.elapsed > const Duration(seconds: 5)) {
        throw TimeoutException('condition not met');
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  /// Register a GET that replies after [delay], keeping the request inflight.
  void onSlowGet(String path, {Duration delay = const Duration(seconds: 1)}) {
    dioAdapter.onGet(
      path,
      (server) => server.reply(200, {'ok': true},
          delay: delay,
          headers: {
            'content-type': ['application/json'],
          }),
    );
  }

  group('cancellation', () {
    test('cancel by key removes the inflight request', () async {
      onSlowGet('/slow');
      await settle(InitializeFetchEvent());

      unawaited(fetchBloc
          .send(GetEvent(url: '/slow', cachePolicy: CachePolicy.networkOnly))
          .catchError((_) {}));

      await pumpUntil(() => fetchBloc.state.inflightCount == 1);

      await fetchBloc.send(CancelRequestEvent(
        key: RequestKey.from(method: 'GET', url: '/slow'),
      ));

      expect(fetchBloc.state.activeRequests, isEmpty);
      expect(fetchBloc.state.inflightCount, 0);
    });

    test('cancel by scope cancels only matching requests', () async {
      onSlowGet('/a');
      onSlowGet('/b');
      await settle(InitializeFetchEvent());

      unawaited(fetchBloc
          .send(GetEvent(
              url: '/a',
              cachePolicy: CachePolicy.networkOnly,
              scope: 'screen1'))
          .catchError((_) {}));
      unawaited(fetchBloc
          .send(GetEvent(
              url: '/b',
              cachePolicy: CachePolicy.networkOnly,
              scope: 'screen2'))
          .catchError((_) {}));

      await pumpUntil(() => fetchBloc.state.inflightCount == 2);

      await fetchBloc.send(CancelScopeEvent(scope: 'screen1'));

      // Only the screen1 request was cancelled; screen2 remains inflight.
      expect(fetchBloc.state.inflightCount, 1);
      final remaining = fetchBloc.state.activeRequests.values.single;
      expect(remaining.scope, 'screen2');
    });

    test('cancel all clears every inflight request', () async {
      onSlowGet('/a');
      onSlowGet('/b');
      await settle(InitializeFetchEvent());

      unawaited(fetchBloc
          .send(GetEvent(url: '/a', cachePolicy: CachePolicy.networkOnly))
          .catchError((_) {}));
      unawaited(fetchBloc
          .send(GetEvent(url: '/b', cachePolicy: CachePolicy.networkOnly))
          .catchError((_) {}));

      await pumpUntil(() => fetchBloc.state.inflightCount == 2);

      await fetchBloc.send(CancelAllEvent());

      expect(fetchBloc.state.activeRequests, isEmpty);
      expect(fetchBloc.state.inflightCount, 0);
    });
  });

  group('coalescing', () {
    test('decode isolation: one wire response, independent decoders', () async {
      dioAdapter.onGet(
        '/shared',
        (server) => server.reply(200, {'id': 7, 'name': 'Ada'},
            delay: const Duration(milliseconds: 80),
            headers: {
              'content-type': ['application/json'],
            }),
      );
      await settle(InitializeFetchEvent());

      int? decodedId;
      String? decodedName;

      // Two concurrent requests for the same key with different decoders.
      await Future.wait([
        fetchBloc.send(GetEvent(
          url: '/shared',
          cachePolicy: CachePolicy.networkOnly,
          decode: (raw) => decodedId = raw['id'] as int,
        )),
        fetchBloc.send(GetEvent(
          url: '/shared',
          cachePolicy: CachePolicy.networkOnly,
          decode: (raw) => decodedName = raw['name'] as String,
        )),
      ]);

      // Each caller decoded the shared response independently.
      expect(decodedId, 7);
      expect(decodedName, 'Ada');
      expect(fetchBloc.state.stats.coalescedCount, greaterThanOrEqualTo(1));
    });

    test('maxConcurrentRequests serializes network calls', () async {
      onSlowGet('/a', delay: const Duration(milliseconds: 120));
      onSlowGet('/b', delay: const Duration(milliseconds: 120));

      await settle(
        InitializeFetchEvent(config: const FetchConfig(maxConcurrentRequests: 1)),
      );

      // Track how many requests are simultaneously in the Dio layer.
      // (Initialize clears interceptors, so add this after init.)
      var concurrent = 0;
      var maxConcurrent = 0;
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          concurrent++;
          maxConcurrent = max(maxConcurrent, concurrent);
          handler.next(options);
        },
        onResponse: (response, handler) {
          concurrent--;
          handler.next(response);
        },
        onError: (error, handler) {
          concurrent--;
          handler.next(error);
        },
      ));

      await Future.wait([
        fetchBloc.send(GetEvent(url: '/a', cachePolicy: CachePolicy.networkOnly)),
        fetchBloc.send(GetEvent(url: '/b', cachePolicy: CachePolicy.networkOnly)),
      ]);

      expect(fetchBloc.state.stats.successCount, 2);
      expect(maxConcurrent, 1);
    });
  });
}
