import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:juice/juice.dart';
import 'package:juice_network/juice_network.dart';

import 'support/cache_test_support.dart';

/// Verifies that `FetchConfig.maxCacheSize` is the limit the cache enforces.
void main() {
  late Dio dio;
  late DioAdapter dioAdapter;
  late Map<String, Uint8List> backing;
  late MockStorageBloc storageBloc;
  FetchBloc? fetchBloc;

  setUp(() {
    dio = Dio();
    dioAdapter = DioAdapter(dio: dio);
    backing = {};
    storageBloc = createStatefulStorageBloc(backing);
  });

  tearDown(() async {
    await fetchBloc?.close();
    fetchBloc = null;
  });

  Future<void> sendAndSettle(FetchBloc bloc, EventBase event) async {
    final completer = Completer<void>();
    late StreamSubscription<StreamStatus<FetchState>> sub;
    sub = bloc.stream.listen((status) {
      if (status is! WaitingStatus) {
        if (!completer.isCompleted) completer.complete();
        sub.cancel();
      }
    });
    try {
      await bloc.send(event);
    } catch (_) {}
    await completer.future.timeout(const Duration(seconds: 5));
  }

  /// Registers [count] endpoints `/big/N`, each replying with about a
  /// kilobyte of JSON, and fetches every one through the cache.
  Future<void> fetchKilobytes(FetchBloc bloc, int count) async {
    for (var i = 0; i < count; i++) {
      dioAdapter.onGet(
        '/big/$i',
        (server) => server.reply(
          200,
          {'i': i, 'pad': 'x' * 1000},
          headers: {
            'content-type': ['application/json'],
          },
        ),
      );
      await sendAndSettle(
        bloc,
        GetEvent(
          url: '/big/$i',
          cachePolicy: CachePolicy.cacheFirst,
          ttl: const Duration(minutes: 5),
        ),
      );
    }
  }

  test('the cache manager starts at the default limit', () {
    final bloc = fetchBloc = FetchBloc(storageBloc: storageBloc, dio: dio);

    expect(bloc.cacheManager.maxCacheSize, const FetchConfig().maxCacheSize);
  });

  test('InitializeFetchEvent applies the configured limit', () async {
    final bloc = fetchBloc = FetchBloc(storageBloc: storageBloc, dio: dio);

    await sendAndSettle(
      bloc,
      InitializeFetchEvent(config: const FetchConfig(maxCacheSize: 4096)),
    );

    expect(bloc.state.config.maxCacheSize, 4096);
    expect(bloc.cacheManager.maxCacheSize, 4096);
  });

  test('withConfig applies the configured limit', () async {
    final bloc = fetchBloc = FetchBloc.withConfig(
      const FetchConfig(maxCacheSize: 4096),
      storageBloc: storageBloc,
      dio: dio,
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(bloc.state.isInitialized, isTrue);
    expect(bloc.cacheManager.maxCacheSize, 4096);
  });

  test('writes past the configured limit are evicted', () async {
    final bloc = fetchBloc = FetchBloc(storageBloc: storageBloc, dio: dio);
    await sendAndSettle(
      bloc,
      InitializeFetchEvent(config: const FetchConfig(maxCacheSize: 4096)),
    );

    await fetchKilobytes(bloc, 8);

    expect(bloc.state.stats.successCount, 8);
    expect(bloc.cacheManager.diskCacheSize, lessThanOrEqualTo(4096));
    expect(backing.length, lessThan(8));
    expect(backing.length, greaterThan(0));
  });

  test('the same writes fit under a larger limit', () async {
    final bloc = fetchBloc = FetchBloc(storageBloc: storageBloc, dio: dio);
    await sendAndSettle(
      bloc,
      InitializeFetchEvent(config: const FetchConfig(maxCacheSize: 1 << 20)),
    );

    await fetchKilobytes(bloc, 8);

    expect(backing.length, 8);
  });
}
