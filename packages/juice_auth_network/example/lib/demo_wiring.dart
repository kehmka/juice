import 'package:juice_auth/juice_auth.dart';
import 'package:juice_auth_network/juice_auth_network.dart';
import 'package:juice_network/juice_network.dart';
import 'package:juice_storage/juice_storage.dart';

import 'demo_auth_provider.dart';
import 'profile_bloc.dart';

/// The wired blocs for the demo.
typedef DemoBlocs = ({
  AuthBloc authBloc,
  FetchBloc fetchBloc,
  ProfileBloc profileBloc,
});

/// Build and wire the demo's blocs using Juice primitives only.
///
/// Every interaction is a bloc event: login, fetch (via [ProfileBloc] →
/// [FetchBloc]), and refresh (via [AuthBloc]). Interceptors are registered
/// through `InitializeFetchEvent` — the framework's interceptor surface.
///
/// Token injection and cache isolation need no transport access. The example
/// therefore wires only those two adapters. Automatic 401 → refresh → retry
/// (`AuthBlocRefreshInterceptor`) replays the request at the Dio layer and so
/// needs a shared `Dio`; that pattern is documented in the package README and
/// covered by the package tests. Here, refresh is driven explicitly through the
/// `RefreshTokenEvent` path instead.
Future<DemoBlocs> buildDemo({required StorageBloc storageBloc}) async {
  final authBloc = AuthBloc.withConfig(
    AuthConfig(
      // Keyed 'email' so AuthBloc.loginWithEmail() (and refresh, which looks up
      // providers[session.providerName]) resolve this provider.
      providers: {'email': DemoAuthProvider()},
      restoreSessionOnInit: false,
    ),
    storageBloc: storageBloc,
  );

  final fetchBloc = FetchBloc(
    storageBloc: storageBloc,
    // Per-user cache isolation, driven by AuthBloc.
    authIdentityProvider: AuthBlocIdentityProvider(authBloc).call,
  );

  await fetchBloc.send(InitializeFetchEvent(
    config: const FetchConfig(baseUrl: 'https://dummyjson.com'),
    interceptors: [
      // Injects the live access token on every request. No transport access.
      AuthBlocAuthInterceptor(authBloc),
    ],
  ));

  final profileBloc = ProfileBloc(fetchBloc: fetchBloc, authBloc: authBloc);

  return (authBloc: authBloc, fetchBloc: fetchBloc, profileBloc: profileBloc);
}
