import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:juice/juice.dart';
import 'package:juice_network/juice_network.dart';

import 'support/cache_test_support.dart';

/// Verifies retry safety: idempotent methods retry on transient failures,
/// non-idempotent methods don't (without explicit opt-in), and retryable
/// POST/PATCH requires an idempotency key.
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

  /// Send an event, returning the error from a [FailureStatus] if one is
  /// emitted (else null). Settles on the first non-waiting status.
  Future<Object?> sendAndCaptureError(EventBase event) async {
    final completer = Completer<Object?>();
    late StreamSubscription<StreamStatus<FetchState>> sub;
    sub = fetchBloc.stream.listen((status) {
      // Retries emit intermediate (non-waiting) stat updates while the request
      // is still inflight; only treat a status as terminal once inflight clears.
      if (status is FailureStatus<FetchState>) {
        if (!completer.isCompleted) completer.complete(status.error);
        sub.cancel();
      } else if (status is! WaitingStatus && status.state.inflightCount == 0) {
        if (!completer.isCompleted) completer.complete(null);
        sub.cancel();
      }
    });
    try {
      await fetchBloc.send(event);
    } catch (_) {}
    return completer.future.timeout(const Duration(seconds: 10));
  }

  group('idempotent methods retry', () {
    test('GET retries on 5xx (retryCount increments)', () async {
      dioAdapter.onGet('/data', (server) => server.reply(500, {'e': 'boom'}));
      await sendAndCaptureError(InitializeFetchEvent());

      final error = await sendAndCaptureError(GetEvent(
        url: '/data',
        cachePolicy: CachePolicy.networkOnly,
        maxAttempts: 2, // one retry, keeps backoff short (~1s)
      ));

      // The retry fired (the meaningful behavior); error-type mapping for 5xx
      // is covered by the POST test. The retried attempt surfaces as a
      // FetchError once attempts are exhausted.
      expect(fetchBloc.state.stats.retryCount, 1);
      expect(error, isA<FetchError>());
    });
  });

  group('non-idempotent methods do not retry by default', () {
    test('POST does not retry on 5xx', () async {
      dioAdapter.onPost(
        '/orders',
        (server) => server.reply(500, {'e': 'boom'}),
        data: const {'item': 'widget'},
      );
      await sendAndCaptureError(InitializeFetchEvent());

      final error = await sendAndCaptureError(PostEvent(
        url: '/orders',
        body: const {'item': 'widget'},
        maxAttempts: 3,
      ));

      expect(fetchBloc.state.stats.retryCount, 0);
      expect(error, isA<ServerError>());
    });
  });

  group('retry opt-in validation', () {
    test('retryable POST without idempotencyKey fails with ArgumentError',
        () async {
      await sendAndCaptureError(InitializeFetchEvent());

      final error = await sendAndCaptureError(PostEvent(
        url: '/orders',
        body: const {'item': 'widget'},
        retryable: true, // opt-in, but no idempotencyKey
      ));

      expect(error, isA<ArgumentError>());
      // No network attempt was made.
      expect(fetchBloc.state.stats.totalRequests, 0);
    });

    test('retryable PATCH without idempotencyKey fails with ArgumentError',
        () async {
      await sendAndCaptureError(InitializeFetchEvent());

      final error = await sendAndCaptureError(PatchEvent(
        url: '/orders/1',
        body: const {'status': 'shipped'},
        retryable: true,
      ));

      expect(error, isA<ArgumentError>());
    });
  });

  group('client errors are not retried', () {
    test('GET does not retry on 404', () async {
      dioAdapter.onGet('/missing', (server) => server.reply(404, {'e': 'nope'}));
      await sendAndCaptureError(InitializeFetchEvent());

      final error = await sendAndCaptureError(GetEvent(
        url: '/missing',
        cachePolicy: CachePolicy.networkOnly,
        maxAttempts: 3,
      ));

      expect(fetchBloc.state.stats.retryCount, 0);
      expect(error, isA<ClientError>());
    });
  });
}
