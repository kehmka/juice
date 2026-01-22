import 'package:flutter/material.dart';
import 'package:juice/juice.dart';
import 'package:juice_routing/juice_routing.dart';

import '../product_bloc.dart';

class AviatorDemoScreen extends StatefulWidget {
  const AviatorDemoScreen({super.key});

  @override
  State<AviatorDemoScreen> createState() => _AviatorDemoScreenState();
}

class _AviatorDemoScreenState extends State<AviatorDemoScreen> {
  late final ProductBloc _productBloc;

  @override
  void initState() {
    super.initState();
    _productBloc = ProductBloc();
  }

  @override
  void dispose() {
    _productBloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final routingBloc = BlocScope.get<RoutingBloc>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Aviator Demo'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => routingBloc.pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Explanation card
            Card(
              color: Colors.amber[50],
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.lightbulb_outline, color: Colors.amber),
                        SizedBox(width: 8),
                        Text(
                          'Aviator Pattern',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Aviators provide loose coupling between use cases and navigation. '
                      'Instead of a use case calling routingBloc.navigate() directly, '
                      'it emits an aviator name. This means:',
                    ),
                    SizedBox(height: 8),
                    Text('• Use cases don\'t depend on routing'),
                    Text('• Navigation intent is separate from routes'),
                    Text('• Easier testing and refactoring'),
                    Text('• Routes can change without touching use cases'),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Code example
            const Text(
              'Use Case Code',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                '''// In the use case - no routing knowledge!
emitUpdate(
  newState: state.copyWith(selected: product),
  aviatorName: 'viewProduct',  // Just intent
  aviatorArgs: {'productId': product.id},
);''',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: Colors.lightGreenAccent,
                ),
              ),
            ),

            const SizedBox(height: 16),

            const Text(
              'Aviator Registration',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                '''// In bloc constructor - maps intent to route
Aviator(
  name: 'viewProduct',
  navigateWhere: (args) {
    final id = args['productId'];
    routingBloc.navigate('/product/\$id');
  },
)''',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: Colors.lightGreenAccent,
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Live demo
            const Text(
              'Live Demo',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            const Text(
              'Tap a product to trigger the SelectProductUseCase, which navigates via aviator:',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 12),

            StreamBuilder(
              stream: _productBloc.stream,
              builder: (context, snapshot) {
                final state = _productBloc.state;
                final status = _productBloc.currentStatus;

                if (status is WaitingStatus) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(),
                    ),
                  );
                }

                return Column(
                  children: state.products.map((product) {
                    final isSelected = state.selectedProduct?.id == product.id;
                    return Card(
                      color: isSelected ? Colors.deepPurple[50] : null,
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.deepPurple,
                          child: Text(
                            product.id,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        title: Text(product.name),
                        subtitle: Text('\$${product.price.toStringAsFixed(2)}'),
                        trailing: isSelected
                            ? const Icon(Icons.check, color: Colors.deepPurple)
                            : const Icon(Icons.chevron_right),
                        onTap: () => _productBloc.selectProduct(product),
                      ),
                    );
                  }).toList(),
                );
              },
            ),

            const SizedBox(height: 16),

            // Selected product info
            StreamBuilder(
              stream: _productBloc.stream,
              builder: (context, snapshot) {
                final selected = _productBloc.state.selectedProduct;
                if (selected == null) return const SizedBox.shrink();

                return Card(
                  color: Colors.green[50],
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.check_circle, color: Colors.green),
                            SizedBox(width: 8),
                            Text(
                              'Aviator Triggered!',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text('Intent: viewProduct'),
                        Text('Args: {productId: ${selected.id}}'),
                        Text('Would navigate to: /product/${selected.id}'),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
