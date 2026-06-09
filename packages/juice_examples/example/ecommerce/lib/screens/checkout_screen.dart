import 'package:juice/juice.dart';
import 'package:juice_routing/juice_routing.dart';
import '../blocs/cart_bloc.dart';
import '../blocs/cart_events.dart';

class CheckoutScreen extends StatelessJuiceWidget<CartBloc> {
  CheckoutScreen({super.key}) : super(groups: const {'cart:items'});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    final state = bloc.state;

    if (state.orderPlaced) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.check_circle, size: 80, color: Colors.green),
                const SizedBox(height: 24),
                Text(
                  'Order Placed!',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Thank you for your purchase.',
                  style: TextStyle(color: Colors.grey[600], fontSize: 16),
                ),
                const SizedBox(height: 32),
                FilledButton(
                  onPressed: () {
                    final routingBloc = BlocScope.get<RoutingBloc>();
                    routingBloc.resetStack('/products');
                  },
                  child: const Text('Continue Shopping'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Order Summary', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          ...state.items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${item.title} x${item.quantity}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '\$${(item.price * item.quantity).toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Subtotal'),
              Text('\$${state.total.toStringAsFixed(2)}'),
            ],
          ),
          const SizedBox(height: 8),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Shipping'),
              Text('Free'),
            ],
          ),
          const Divider(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold)),
              Text(
                '\$${state.total.toStringAsFixed(2)}',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              onPressed:
                  state.isCheckingOut ? null : () => bloc.send(CheckoutEvent()),
              child: state.isCheckingOut
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Place Order'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget close(BuildContext context) => const SizedBox.shrink();
}
