import 'package:flutter/material.dart';
import 'package:juice/juice.dart';
import 'package:juice_routing/juice_routing.dart';

class DemoScreen extends StatelessWidget {
  const DemoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final routingBloc = BlocScope.get<RoutingBloc>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Demo'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => routingBloc.pop(),
        ),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.science_outlined,
              size: 64,
              color: Colors.deepPurple,
            ),
            const SizedBox(height: 16),
            const Text(
              'Demo Screen',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'This screen is used for navigation type demos.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 32),
            StreamBuilder(
              stream: routingBloc.stream,
              builder: (context, snapshot) {
                final state = routingBloc.state;
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 24),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Text('Stack depth: ${state.stackDepth}'),
                        Text('Current path: ${state.currentPath}'),
                        Text('Can pop: ${state.canPop}'),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => routingBloc.pop(),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Go Back'),
            ),
          ],
        ),
      ),
    );
  }
}
