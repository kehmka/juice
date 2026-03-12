import 'package:flutter/material.dart';
import 'package:juice/juice.dart';
import 'package:juice_routing/juice_routing.dart';
import '../blocs/cart_bloc.dart';
import '../blocs/cart_events.dart';
import '../models/cart_item.dart';

class CartScreen extends StatelessJuiceWidget<CartBloc> {
  CartScreen({super.key}) : super(groups: const {'cart:items'});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    final state = bloc.state;

    return Scaffold(
      appBar: AppBar(title: const Text('Cart')),
      body: state.items.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.shopping_cart_outlined,
                      size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text('Your cart is empty',
                      style: TextStyle(color: Colors.grey[600], fontSize: 16)),
                ],
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: state.items.length,
                    itemBuilder: (context, index) {
                      return _CartItemTile(
                        item: state.items[index],
                        onRemove: () => bloc.send(RemoveFromCartEvent(
                            productId: state.items[index].productId)),
                        onUpdateQuantity: (qty) =>
                            bloc.send(UpdateCartQuantityEvent(
                          productId: state.items[index].productId,
                          quantity: qty,
                        )),
                      );
                    },
                  ),
                ),
                _CartSummary(
                  total: state.total,
                  itemCount: state.itemCount,
                  onCheckout: () {
                    final routingBloc = BlocScope.get<RoutingBloc>();
                    routingBloc.navigate('/checkout');
                  },
                ),
              ],
            ),
    );
  }

  @override
  Widget close(BuildContext context) => const SizedBox.shrink();
}

class _CartItemTile extends StatelessWidget {
  final CartItem item;
  final VoidCallback onRemove;
  final void Function(int) onUpdateQuantity;

  const _CartItemTile({
    required this.item,
    required this.onRemove,
    required this.onUpdateQuantity,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey(item.productId),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.red,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => onRemove(),
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: item.thumbnail.isNotEmpty
                    ? Image.network(item.thumbnail, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const Icon(Icons.shopping_bag))
                    : const Icon(Icons.shopping_bag),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text('\$${item.price.toStringAsFixed(2)}',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.primary)),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline, size: 20),
                    onPressed: () =>
                        onUpdateQuantity(item.quantity - 1),
                  ),
                  Text('${item.quantity}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline, size: 20),
                    onPressed: () =>
                        onUpdateQuantity(item.quantity + 1),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CartSummary extends StatelessWidget {
  final double total;
  final int itemCount;
  final VoidCallback onCheckout;

  const _CartSummary({
    required this.total,
    required this.itemCount,
    required this.onCheckout,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$itemCount items',
                      style: TextStyle(color: Colors.grey[600])),
                  Text(
                    '\$${total.toStringAsFixed(2)}',
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            FilledButton(
              onPressed: onCheckout,
              child: const Text('Checkout'),
            ),
          ],
        ),
      ),
    );
  }
}
