import 'package:juice/juice.dart';
import 'package:juice_auth/juice_auth.dart';

import 'profile_bloc.dart';

/// Single-screen demo of `juice_auth_network`, bound to [AuthBloc] for auth
/// status. The authenticated request results render in [_ProfilePanel], bound
/// to [ProfileBloc].
class HomeScreen extends StatelessJuiceWidget<AuthBloc> {
  HomeScreen({super.key})
      : super(groups: {AuthGroups.status, AuthGroups.session});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    final state = bloc.state;

    return Scaffold(
      appBar: AppBar(title: const Text('juice_auth_network demo')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: state.isAuthenticated
            ? _authenticated(context, state)
            : _loggedOut(),
      ),
    );
  }

  Widget _loggedOut() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('Not signed in'),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('login'),
            onPressed: () => bloc.loginWithEmail('ada@demo.dev', 'password'),
            child: const Text('Log in'),
          ),
        ],
      ),
    );
  }

  Widget _authenticated(BuildContext context, AuthState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Signed in as ${state.user?.displayName} (${state.userId})'),
        const SizedBox(height: 4),
        Text('Access token: ${state.session?.accessToken}',
            key: const Key('token')),
        const Divider(height: 32),
        Row(
          children: [
            FilledButton(
              key: const Key('fetch'),
              onPressed: () => BlocScope.get<ProfileBloc>().load(),
              child: const Text('Fetch /profile'),
            ),
            const SizedBox(width: 12),
            OutlinedButton(
              key: const Key('refresh'),
              onPressed: () => bloc.refreshToken(),
              child: const Text('Force refresh'),
            ),
            const SizedBox(width: 12),
            TextButton(
              key: const Key('logout'),
              onPressed: () => bloc.logout(force: true),
              child: const Text('Log out'),
            ),
          ],
        ),
        const Divider(height: 32),
        Expanded(child: _ProfilePanel()),
      ],
    );
  }
}

/// Renders the authenticated request result, bound to [ProfileBloc].
class _ProfilePanel extends StatelessJuiceWidget<ProfileBloc> {
  _ProfilePanel() : super(groups: {ProfileGroups.profile});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    final state = bloc.state;

    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Authenticated request', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Text(
          'Injected token: ${state.injectedToken ?? '— (tap Fetch)'}',
          key: const Key('injectedToken'),
          style: const TextStyle(fontFamily: 'monospace'),
        ),
        const SizedBox(height: 8),
        Text(
          'Response: ${state.error ?? state.profileBody ?? '—'}',
          key: const Key('response'),
          style: const TextStyle(fontFamily: 'monospace'),
        ),
      ],
    );
  }
}
