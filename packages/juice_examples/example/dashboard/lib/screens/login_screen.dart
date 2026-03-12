import 'package:flutter/material.dart';
import 'package:juice/juice.dart';
import 'package:juice_auth/juice_auth.dart';
import 'package:juice_routing/juice_routing.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _fillCredentials(String email, String password) {
    _emailController.text = email;
    _passwordController.text = password;
  }

  Future<void> _login() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    if (email.isEmpty || password.isEmpty) return;

    setState(() => _isLoading = true);

    final authBloc = BlocScope.get<AuthBloc>();
    authBloc.send(LoginEvent(
      providerName: 'email',
      credentials: EmailCredentials(email: email, password: password),
    ));

    // Wait for auth state change
    await authBloc.stream.firstWhere((status) {
      final state = authBloc.state;
      return state.isAuthenticated || state.lastError != null;
    });

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (authBloc.state.isAuthenticated) {
      final routingBloc = BlocScope.get<RoutingBloc>();
      routingBloc.navigate('/dashboard');
    } else if (authBloc.state.lastError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(authBloc.state.lastError.toString()),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.dashboard_rounded,
                  size: 64,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'Admin Dashboard',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Sign in to continue',
                  style: TextStyle(color: Colors.grey[600]),
                ),
                const SizedBox(height: 32),

                // Demo credential chips
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _CredentialChip(
                      label: 'Admin',
                      onTap: () => _fillCredentials('admin@demo.com', 'admin'),
                    ),
                    _CredentialChip(
                      label: 'Editor',
                      onTap: () =>
                          _fillCredentials('editor@demo.com', 'editor'),
                    ),
                    _CredentialChip(
                      label: 'Viewer',
                      onTap: () =>
                          _fillCredentials('viewer@demo.com', 'viewer'),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                TextField(
                  controller: _emailController,
                  decoration: InputDecoration(
                    labelText: 'Email',
                    prefixIcon: const Icon(Icons.email_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  obscureText: true,
                  onSubmitted: (_) => _login(),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    onPressed: _isLoading ? null : _login,
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Sign In'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CredentialChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _CredentialChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label),
      avatar: const Icon(Icons.person_outline, size: 18),
      onPressed: onTap,
    );
  }
}
