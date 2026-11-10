import 'package:juice/juice.dart';
import '../auth_bloc.dart';
import '../events/auth_events.dart';
import '../../user_profile/user_profile_bloc.dart';

/// Example page demonstrating a Reaction for bloc-to-bloc communication.
///
/// This page shows:
/// - AuthBloc handling login/logout
/// - UserProfileBloc reacting to AuthBloc's state through a Reaction
class AuthPage extends StatelessWidget {
  const AuthPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Auth & Reactions Demo'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildExplanation(),
            const SizedBox(height: 24),
            _AuthStatusCard(),
            const SizedBox(height: 16),
            _UserProfileCard(),
            const SizedBox(height: 24),
            _LoginForm(),
          ],
        ),
      ),
    );
  }

  Widget _buildExplanation() {
    return Card(
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Reaction Demo',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: Colors.blue.shade900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'UserProfileBloc reacts to AuthBloc\'s state:\n'
              '• becomes authenticated → LoadProfileEvent\n'
              '• becomes unauthenticated → ClearProfileEvent\n\n'
              'UserProfileBloc owns both reactions. AuthBloc only emits its state.',
              style: TextStyle(color: Colors.blue.shade800),
            ),
          ],
        ),
      ),
    );
  }
}

class _AuthStatusCard extends StatelessJuiceWidget<AuthBloc> {
  _AuthStatusCard() : super(groups: {'auth'});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    final state = bloc.state;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  state.isAuthenticated ? Icons.check_circle : Icons.cancel,
                  color: state.isAuthenticated ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 8),
                Text(
                  'Auth Status',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (state.isLoading)
              const LinearProgressIndicator()
            else
              Text(
                state.isAuthenticated
                    ? 'Logged in as ${state.email}'
                    : 'Not logged in',
              ),
          ],
        ),
      ),
    );
  }
}

class _UserProfileCard extends StatelessJuiceWidget<UserProfileBloc> {
  _UserProfileCard() : super(groups: {'profile'});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    final state = bloc.state;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  state.hasProfile ? Icons.person : Icons.person_outline,
                  color: state.hasProfile ? Colors.blue : Colors.grey,
                ),
                const SizedBox(width: 8),
                Text(
                  'User Profile (via Reaction)',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (state.isLoading)
              const Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 8),
                  Text('Loading profile...'),
                ],
              )
            else if (state.hasProfile)
              Row(
                children: [
                  CircleAvatar(
                    backgroundImage: NetworkImage(state.avatarUrl!),
                    radius: 24,
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        state.displayName!,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'ID: ${state.userId}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ],
              )
            else
              const Text('No profile loaded'),
          ],
        ),
      ),
    );
  }
}

class _LoginForm extends StatelessJuiceWidget<AuthBloc> {
  _LoginForm() : super(groups: {'auth'});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    final state = bloc.state;

    if (state.isAuthenticated) {
      return ElevatedButton.icon(
        onPressed: state.isLoading ? null : () => bloc.send(LogoutEvent()),
        icon: const Icon(Icons.logout),
        label: const Text('Logout'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.red.shade100,
          foregroundColor: Colors.red.shade900,
        ),
      );
    }

    return ElevatedButton.icon(
      onPressed: state.isLoading
          ? null
          : () => bloc.send(LoginEvent(
                email: 'demo@example.com',
                password: 'password',
              )),
      icon: state.isLoading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.login),
      label:
          Text(state.isLoading ? 'Logging in...' : 'Login as demo@example.com'),
    );
  }
}
