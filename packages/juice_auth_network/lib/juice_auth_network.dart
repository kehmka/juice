/// Integration glue between [juice_auth](https://pub.dev/packages/juice_auth)
/// and [juice_network](https://pub.dev/packages/juice_network).
///
/// Wires an `AuthBloc` into a `FetchBloc` so authenticated requests, 401 token
/// refresh, and per-user cache isolation work without hand-written plumbing.
///
/// ```dart
/// final dio = Dio();
/// final fetchBloc = FetchBloc(
///   storageBloc: storageBloc,
///   dio: dio,
///   authIdentityProvider: AuthBlocIdentityProvider(authBloc).call,
/// );
/// fetchBloc.send(InitializeFetchEvent(
///   config: FetchConfig(baseUrl: 'https://api.example.com'),
///   interceptors: [
///     AuthBlocAuthInterceptor(authBloc),
///     AuthBlocRefreshInterceptor(authBloc, dio: dio),
///   ],
/// ));
/// ```
library juice_auth_network;

export 'src/auth_identity_provider.dart';
export 'src/auth_token_provider.dart';
export 'src/auth_refresh_strategy.dart';
