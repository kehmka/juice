import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:juice/juice.dart';
import 'package:juice_network/juice_network.dart';

import 'support/cache_test_support.dart';

class _SubclassedAuthInterceptor extends AuthInterceptor {
  _SubclassedAuthInterceptor() : super(tokenProvider: () async => 'sub-token');
}

/// Verifies that the cache and the coalescer never hand one credential's
/// response to another: an explicit `Authorization` header is scoped by its
/// own digest, and interceptor-injected auth is refused unless the bloc has
/// an `authIdentityProvider`.
void main() {
  late Dio dio;
  late DioAdapter dioAdapter;
  late Map<String, Uint8List> backing;
  late MockStorageBloc storageBloc;
  late List<FetchBloc> blocs;

  /// Requests that reached the network, by path.
  late List<String> sent;

  setUp(() {
    dio = Dio();
    dioAdapter = DioAdapter(dio: dio);
    backing = {};
    storageBloc = createStatefulStorageBloc(backing);
    blocs = [];
    sent = [];
  });

  tearDown(() async {
    for (final bloc in blocs) {
      await bloc.close();
    }
  });

  FetchBloc build({AuthIdentityProvider? authIdentityProvider}) {
    final bloc = FetchBloc(
      storageBloc: storageBloc,
      dio: dio,
      authIdentityProvider: authIdentityProvider,
    );
    blocs.add(bloc);
    return bloc;
  }

  /// Sends [event] and returns the first status that is not a waiting one.
  Future<StreamStatus<FetchState>> sendAndSettle(
    FetchBloc bloc,
    EventBase event,
  ) async {
    final completer = Completer<StreamStatus<FetchState>>();
    late StreamSubscription<StreamStatus<FetchState>> sub;
    sub = bloc.stream.listen((status) {
      if (status is! WaitingStatus) {
        if (!completer.isCompleted) completer.complete(status);
        sub.cancel();
      }
    });
    try {
      await bloc.send(event);
    } catch (_) {}
    return completer.future.timeout(const Duration(seconds: 5));
  }

  /// Counts what reaches the network. Initialization and reconfiguration
  /// replace the Dio interceptors, so this is added after them.
  void countNetworkCalls() {
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        sent.add(options.path);
        handler.next(options);
      },
    ));
  }

  void onGet(String path, Object body, {Duration? delay}) {
    dioAdapter.onGet(
      path,
      (server) => server.reply(
        200,
        body,
        headers: {
          'content-type': ['application/json'],
        },
        delay: delay,
      ),
    );
  }

  int installed(Dio dio) =>
      dio.interceptors.whereType<FetchInterceptorAdapter>().length;

  GetEvent cachedGet(String url, Map<String, String> headers) => GetEvent(
        url: url,
        cachePolicy: CachePolicy.cacheFirst,
        ttl: const Duration(minutes: 5),
        headers: headers,
        cacheAuthResponses: true,
      );

  group('explicit Authorization header', () {
    test('two bearer tokens do not share a cached response', () async {
      onGet('/profile', {'id': 1});
      final bloc = build();
      await sendAndSettle(bloc, InitializeFetchEvent());
      countNetworkCalls();

      await sendAndSettle(
          bloc, cachedGet('/profile', {'Authorization': 'Bearer alice-token'}));
      await sendAndSettle(
          bloc, cachedGet('/profile', {'Authorization': 'Bearer bob-token'}));

      expect(sent, ['/profile', '/profile']);
      expect(bloc.state.stats.cacheHits, 0);
      expect(backing.length, 2); // one entry per credential
    });

    test('the same token reads its own cached response', () async {
      onGet('/profile', {'id': 1});
      final bloc = build();
      await sendAndSettle(bloc, InitializeFetchEvent());
      countNetworkCalls();

      const auth = {'Authorization': 'Bearer alice-token'};
      await sendAndSettle(bloc, cachedGet('/profile', auth));
      await sendAndSettle(bloc, cachedGet('/profile', auth));

      expect(sent, ['/profile']);
      expect(bloc.state.stats.cacheHits, 1);
    });

    test('two basic credentials do not share a cached response', () async {
      onGet('/profile', {'id': 1});
      final bloc = build();
      await sendAndSettle(bloc, InitializeFetchEvent());
      countNetworkCalls();

      await sendAndSettle(
          bloc, cachedGet('/profile', {'Authorization': 'Basic YWxpY2U6eA=='}));
      await sendAndSettle(
          bloc, cachedGet('/profile', {'Authorization': 'Basic Ym9iOng='}));

      expect(sent, ['/profile', '/profile']);
      expect(bloc.state.stats.cacheHits, 0);
    });

    test('two bearer tokens in flight together are not coalesced', () async {
      onGet('/profile', {'id': 1}, delay: const Duration(milliseconds: 50));
      final bloc = build();
      await sendAndSettle(bloc, InitializeFetchEvent());
      countNetworkCalls();

      GetEvent get(String token) => GetEvent(
            url: '/profile',
            cachePolicy: CachePolicy.networkOnly,
            headers: {'Authorization': 'Bearer $token'},
          );
      bloc.send(get('alice-token'));
      bloc.send(get('bob-token'));
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(sent, ['/profile', '/profile']);
      expect(bloc.state.stats.coalescedCount, 0);
      expect(bloc.state.stats.successCount, 2);
    });

    test('the credential is not written into the cache key', () async {
      onGet('/profile', {'id': 1});
      final bloc = build();
      await sendAndSettle(bloc, InitializeFetchEvent());

      await sendAndSettle(
          bloc, cachedGet('/profile', {'Authorization': 'Bearer alice-token'}));

      expect(backing.keys, hasLength(1));
      expect(backing.keys.single, isNot(contains('alice-token')));
      expect(backing.keys.single, startsWith('GET:/profile'));
    });

    test('a lowercase authorization header is not cached by default', () async {
      onGet('/profile', {'id': 1});
      final bloc = build();
      await sendAndSettle(bloc, InitializeFetchEvent());

      await sendAndSettle(
        bloc,
        GetEvent(
          url: '/profile',
          cachePolicy: CachePolicy.cacheFirst,
          ttl: const Duration(minutes: 5),
          headers: {'authorization': 'Bearer alice-token'},
        ),
      );

      expect(bloc.state.stats.successCount, 1);
      expect(backing, isEmpty);
    });
  });

  group('AuthInterceptor without an authIdentityProvider', () {
    test('withConfig throws', () {
      expect(
        () => FetchBloc.withConfig(
          const FetchConfig(),
          storageBloc: storageBloc,
          dio: dio,
          interceptors: [AuthInterceptor(tokenProvider: () async => 't')],
        ),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          allOf(contains('AuthInterceptor'), contains('authIdentityProvider')),
        )),
      );
    });

    test('InitializeFetchEvent is refused and the bloc stays uninitialized',
        () async {
      final bloc = build();

      final status = await sendAndSettle(
        bloc,
        InitializeFetchEvent(
          config: const FetchConfig(baseUrl: 'https://api.example.com'),
          interceptors: [AuthInterceptor(tokenProvider: () async => 't')],
        ),
      );

      expect(status, isA<FailureStatus<FetchState>>());
      final error = (status as FailureStatus<FetchState>).error;
      expect(error, isA<StateError>());
      expect((error as StateError).message, contains('authIdentityProvider'));
      expect(bloc.state.isInitialized, isFalse);
      expect(installed(dio), 0);
      expect(dio.options.baseUrl, isEmpty);
    });

    test('a subclass of AuthInterceptor is refused the same way', () async {
      final bloc = build();

      final status = await sendAndSettle(
        bloc,
        InitializeFetchEvent(interceptors: [_SubclassedAuthInterceptor()]),
      );

      expect(status, isA<FailureStatus<FetchState>>());
      expect(
        ((status as FailureStatus<FetchState>).error as StateError).message,
        contains('_SubclassedAuthInterceptor'),
      );
      expect(bloc.state.isInitialized, isFalse);
    });

    test('a refused initialization can be followed by a valid one', () async {
      final bloc = build();
      await sendAndSettle(
        bloc,
        InitializeFetchEvent(
          interceptors: [AuthInterceptor(tokenProvider: () async => 't')],
        ),
      );
      expect(bloc.state.isInitialized, isFalse);

      await sendAndSettle(
        bloc,
        InitializeFetchEvent(interceptors: [TimingInterceptor()]),
      );

      expect(bloc.state.isInitialized, isTrue);
      expect(installed(dio), 1);
    });

    test(
        'ReconfigureInterceptorsEvent is refused and the installed '
        'interceptors stay', () async {
      final bloc = build();
      await sendAndSettle(
        bloc,
        InitializeFetchEvent(interceptors: [TimingInterceptor()]),
      );
      final before = dio.interceptors.toList();

      final status = await sendAndSettle(
        bloc,
        ReconfigureInterceptorsEvent(interceptors: [
          TimingInterceptor(),
          AuthInterceptor(tokenProvider: () async => 't'),
        ]),
      );

      expect(status, isA<FailureStatus<FetchState>>());
      expect((status as FailureStatus<FetchState>).error, isA<StateError>());
      expect(dio.interceptors.toList(), before);
    });

    test('an ApiKeyInterceptor needs no identity provider', () async {
      final bloc = build();

      await sendAndSettle(
        bloc,
        InitializeFetchEvent(interceptors: [ApiKeyInterceptor(apiKey: 'k')]),
      );

      expect(bloc.state.isInitialized, isTrue);
      expect(installed(dio), 1);
    });
  });

  group('AuthInterceptor with an authIdentityProvider', () {
    test('withConfig initializes', () async {
      final bloc = FetchBloc.withConfig(
        const FetchConfig(),
        storageBloc: storageBloc,
        dio: dio,
        authIdentityProvider: () => 'alice',
        interceptors: [AuthInterceptor(tokenProvider: () async => 't')],
      );
      blocs.add(bloc);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(bloc.state.isInitialized, isTrue);
      expect(installed(dio), 1);
    });

    test('ReconfigureInterceptorsEvent installs it', () async {
      final bloc = build(authIdentityProvider: () => 'alice');
      await sendAndSettle(bloc, InitializeFetchEvent());
      expect(installed(dio), 0);

      await bloc.send(ReconfigureInterceptorsEvent(interceptors: [
        TimingInterceptor(),
        AuthInterceptor(tokenProvider: () async => 't'),
      ]));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(installed(dio), 2);
    });

    test('two users do not share a cached response', () async {
      onGet('/me', {'id': 1});
      var user = 'alice';
      final bloc = build(authIdentityProvider: () => user);
      await sendAndSettle(
        bloc,
        InitializeFetchEvent(interceptors: [
          AuthInterceptor(tokenProvider: () async => '$user-token'),
        ]),
      );
      countNetworkCalls();

      GetEvent get() => GetEvent(
            url: '/me',
            cachePolicy: CachePolicy.cacheFirst,
            ttl: const Duration(minutes: 5),
          );
      await sendAndSettle(bloc, get());
      user = 'bob';
      await sendAndSettle(bloc, get());
      await sendAndSettle(bloc, get());

      expect(sent, ['/me', '/me']); // bob's first read went to the network
      expect(bloc.state.stats.cacheHits, 1); // bob's second read
      expect(backing.length, 2);
    });
  });
}
