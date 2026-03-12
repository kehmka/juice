import 'package:flutter/material.dart';
import 'package:juice/juice.dart';
import '../blocs/products_bloc.dart';
import '../blocs/cart_bloc.dart';
import '../blocs/cart_events.dart';

/// Demonstrates JuiceBuilder2 — observing ProductsBloc and CartBloc together.
class ProductDetailScreen extends StatelessWidget {
  const ProductDetailScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return JuiceBuilder2<ProductsBloc, CartBloc>(
      groups: const {'products:detail', 'cart:items'},
      builder: (context, productsBloc, cartBloc, status) {
        final product = productsBloc.state.selectedProduct;

        if (product == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        final inCart =
            cartBloc.state.items.any((i) => i.productId == product.id);

        return Scaffold(
          appBar: AppBar(title: Text(product.title)),
          body: ListView(
            children: [
              // Image carousel placeholder
              SizedBox(
                height: 300,
                child: product.images.isNotEmpty
                    ? PageView.builder(
                        itemCount: product.images.length,
                        itemBuilder: (context, index) {
                          return Image.network(
                            product.images[index],
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) =>
                                const Center(child: Icon(Icons.image, size: 64)),
                          );
                        },
                      )
                    : Container(
                        color: Colors.grey[100],
                        child: const Center(
                            child: Icon(Icons.shopping_bag, size: 64)),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.title,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 4),
                    if (product.brand.isNotEmpty)
                      Text(product.brand,
                          style: TextStyle(color: Colors.grey[600])),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '\$${product.discountedPrice.toStringAsFixed(2)}',
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                        ),
                        if (product.discountPercentage > 0) ...[
                          const SizedBox(width: 8),
                          Text(
                            '\$${product.price.toStringAsFixed(2)}',
                            style: const TextStyle(
                              decoration: TextDecoration.lineThrough,
                              color: Colors.grey,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.red[50],
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '-${product.discountPercentage.toStringAsFixed(0)}%',
                              style: const TextStyle(
                                  color: Colors.red,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(Icons.star, color: Colors.amber, size: 20),
                        const SizedBox(width: 4),
                        Text('${product.rating} rating'),
                        const SizedBox(width: 16),
                        Icon(
                          product.stock > 0
                              ? Icons.check_circle
                              : Icons.cancel,
                          size: 18,
                          color:
                              product.stock > 0 ? Colors.green : Colors.red,
                        ),
                        const SizedBox(width: 4),
                        Text(product.stock > 0
                            ? '${product.stock} in stock'
                            : 'Out of stock'),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      product.description,
                      style: const TextStyle(fontSize: 15, height: 1.5),
                    ),
                    const SizedBox(height: 8),
                    Chip(
                      label: Text(product.category),
                      visualDensity: VisualDensity.compact,
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton.icon(
                        onPressed: inCart
                            ? null
                            : () {
                                cartBloc.send(
                                    AddToCartEvent(product: product));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                        '${product.title} added to cart'),
                                    duration:
                                        const Duration(seconds: 1),
                                  ),
                                );
                              },
                        icon: Icon(
                            inCart ? Icons.check : Icons.add_shopping_cart),
                        label: Text(inCart ? 'In Cart' : 'Add to Cart'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
