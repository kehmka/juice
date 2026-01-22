import 'package:flutter/material.dart';
import 'package:juice/juice.dart';
import 'package:juice_routing/juice_routing.dart';

class NotFoundScreen extends StatelessWidget {
  const NotFoundScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final routingBloc = BlocScope.get<RoutingBloc>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Not Found'),
        backgroundColor: Colors.red[100],
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (routingBloc.state.canPop) {
              routingBloc.pop();
            } else {
              routingBloc.navigate('/');
            }
          },
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                size: 80,
                color: Colors.red,
              ),
              const SizedBox(height: 24),
              const Text(
                '404',
                style: TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Page Not Found',
                style: TextStyle(fontSize: 24),
              ),
              const SizedBox(height: 16),
              const Text(
                'The route you requested does not exist.',
                style: TextStyle(color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: () => routingBloc.navigate('/'),
                icon: const Icon(Icons.home),
                label: const Text('Go Home'),
              ),
              const SizedBox(height: 12),
              if (routingBloc.state.canPop)
                OutlinedButton.icon(
                  onPressed: () => routingBloc.pop(),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Go Back'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
