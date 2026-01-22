import 'package:flutter/material.dart';
import 'package:juice/juice.dart';
import 'package:juice_routing/juice_routing.dart';

import '../auth_bloc.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController(text: 'demo_user');

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  void _login() {
    final authBloc = BlocScope.get<AuthBloc>();
    final routingBloc = BlocScope.get<RoutingBloc>();

    final username = _usernameController.text.trim();
    if (username.isEmpty) return;

    authBloc.login(username);

    // Navigate to home after login
    // In a real app, you might use the returnTo from the redirect
    Future.delayed(const Duration(milliseconds: 600), () {
      routingBloc.navigate('/');
    });
  }

  @override
  Widget build(BuildContext context) {
    final routingBloc = BlocScope.get<RoutingBloc>();
    final authBloc = BlocScope.get<AuthBloc>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Login'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => routingBloc.pop(),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
            const Icon(
              Icons.lock_outline,
              size: 64,
              color: Colors.deepPurple,
            ),
            const SizedBox(height: 24),
            const Text(
              'Welcome Back',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Sign in to access protected routes',
              style: TextStyle(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(
                labelText: 'Username',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person),
              ),
            ),
            const SizedBox(height: 16),
            StreamBuilder(
              stream: authBloc.stream,
              builder: (context, snapshot) {
                final isLoading = authBloc.currentStatus is WaitingStatus;

                return FilledButton(
                  onPressed: isLoading ? null : _login,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Sign In'),
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
            Card(
              color: Colors.blue[50],
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'This demonstrates the GuestGuard - if you\'re already logged in, you\'ll be redirected away from this page.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            ],
          ),
        ),
      ),
    );
  }
}
