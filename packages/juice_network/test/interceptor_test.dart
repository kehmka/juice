import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:juice_network/juice_network.dart';

void main() {
  group('AuthInterceptor', () {
    test('adds Bearer authorization header', () async {
      final interceptor =
          AuthInterceptor(tokenProvider: () async => 'tok123');
      final result =
          await interceptor.onRequest(RequestOptions(path: '/x'));
      expect(result.headers['Authorization'], 'Bearer tok123');
    });

    test('does not override an existing authorization header', () async {
      final interceptor =
          AuthInterceptor(tokenProvider: () async => 'tok123');
      final options = RequestOptions(
        path: '/x',
        headers: {'Authorization': 'Bearer preset'},
      );
      final result = await interceptor.onRequest(options);
      expect(result.headers['Authorization'], 'Bearer preset');
    });

    test('skips auth when skipAuth matches the path', () async {
      final interceptor = AuthInterceptor(
        tokenProvider: () async => 'tok123',
        skipAuth: (path) => path.startsWith('/public'),
      );
      final result =
          await interceptor.onRequest(RequestOptions(path: '/public/info'));
      expect(result.headers.containsKey('Authorization'), isFalse);
    });

    test('adds no header when token is null', () async {
      final interceptor = AuthInterceptor(tokenProvider: () async => null);
      final result =
          await interceptor.onRequest(RequestOptions(path: '/x'));
      expect(result.headers.containsKey('Authorization'), isFalse);
    });
  });

  group('ApiKeyInterceptor', () {
    test('adds API key header by default', () async {
      final interceptor =
          ApiKeyInterceptor(apiKey: 'secret', headerName: 'X-API-Key');
      final result =
          await interceptor.onRequest(RequestOptions(path: '/x'));
      expect(result.headers['X-API-Key'], 'secret');
    });

    test('adds API key as query parameter when configured', () async {
      final interceptor = ApiKeyInterceptor(
        apiKey: 'secret',
        asQueryParam: true,
        queryParamName: 'api_key',
      );
      final result =
          await interceptor.onRequest(RequestOptions(path: '/x'));
      expect(result.queryParameters['api_key'], 'secret');
    });
  });

  group('ETagInterceptor', () {
    test('adds If-None-Match for GET when an ETag is cached', () async {
      final interceptor = ETagInterceptor(getETag: (_) async => '"abc"');
      final result = await interceptor
          .onRequest(RequestOptions(path: '/data', method: 'GET'));
      expect(result.headers['If-None-Match'], '"abc"');
    });

    test('does not add conditional headers for non-GET requests', () async {
      final interceptor = ETagInterceptor(getETag: (_) async => '"abc"');
      final result = await interceptor
          .onRequest(RequestOptions(path: '/data', method: 'POST'));
      expect(result.headers.containsKey('If-None-Match'), isFalse);
    });

    test('saves ETag from response, then sends it on the next request',
        () async {
      final cache = InMemoryETagCache();
      final interceptor = ETagInterceptor(
        getETag: cache.getETag,
        saveETag: cache.saveETag,
      );

      final reqOptions = RequestOptions(path: '/data', method: 'GET');
      await interceptor.onResponse(Response(
        requestOptions: reqOptions,
        statusCode: 200,
        headers: Headers.fromMap({
          'etag': ['"v1"'],
        }),
      ));

      // Next request for the same URL carries the saved ETag.
      final next = await interceptor
          .onRequest(RequestOptions(path: '/data', method: 'GET'));
      expect(next.headers['If-None-Match'], '"v1"');
    });

    test('marks 304 Not Modified and notifies', () async {
      var notModifiedUrl = '';
      final interceptor = ETagInterceptor(
        getETag: (_) async => null,
        onNotModified: (url) async => notModifiedUrl = url,
      );
      final options = RequestOptions(path: '/data');
      await interceptor.onError(DioException(
        requestOptions: options,
        response: Response(requestOptions: options, statusCode: 304),
        type: DioExceptionType.badResponse,
      ));

      expect(options.extra['_notModified'], isTrue);
      expect(notModifiedUrl, isNotEmpty);
    });
  });

  group('RefreshTokenInterceptor', () {
    late Dio dio;

    setUp(() {
      dio = Dio();
      final adapter = DioAdapter(dio: dio);
      adapter.onGet('/x', (server) => server.reply(200, {'ok': true}));
    });

    DioException make401() {
      final options = RequestOptions(path: '/x', method: 'GET');
      return DioException(
        requestOptions: options,
        response: Response(requestOptions: options, statusCode: 401),
        type: DioExceptionType.badResponse,
      );
    }

    test('singleflight: concurrent 401s trigger exactly one refresh', () async {
      var refreshCount = 0;
      final interceptor = RefreshTokenInterceptor(
        dio: dio,
        refreshToken: () async {
          refreshCount++;
          await Future<void>.delayed(const Duration(milliseconds: 50));
          return 'new-token';
        },
      );

      // Fire several 401 handlers concurrently; the singleflight lock must
      // collapse them into a single refresh, and all should recover.
      final results = await Future.wait([
        for (var i = 0; i < 5; i++) interceptor.onError(make401()),
      ]);

      expect(refreshCount, 1);
      expect(results.every((r) => r is Response), isTrue);
    });

    test('non-refresh status codes are passed through untouched', () async {
      var refreshCount = 0;
      final interceptor = RefreshTokenInterceptor(
        dio: dio,
        refreshToken: () async {
          refreshCount++;
          return 'new-token';
        },
      );

      final options = RequestOptions(path: '/x');
      final err = DioException(
        requestOptions: options,
        response: Response(requestOptions: options, statusCode: 500),
        type: DioExceptionType.badResponse,
      );
      final result = await interceptor.onError(err);

      expect(refreshCount, 0);
      expect(result, same(err));
    });

    test('does not refresh again for an already-retried request', () async {
      var refreshCount = 0;
      final interceptor = RefreshTokenInterceptor(
        dio: dio,
        refreshToken: () async {
          refreshCount++;
          return 'new-token';
        },
      );

      final options = RequestOptions(path: '/x')
        ..extra['_isRetryAfterRefresh'] = true;
      final err = DioException(
        requestOptions: options,
        response: Response(requestOptions: options, statusCode: 401),
        type: DioExceptionType.badResponse,
      );
      final result = await interceptor.onError(err);

      expect(refreshCount, 0);
      expect(result, same(err));
    });
  });
}
