import 'package:flutter/material.dart';
import 'package:juice/juice.dart';
import 'package:juice_routing/juice_routing.dart';
import '../blocs/products_bloc.dart';
import '../blocs/products_events.dart';
import '../blocs/cart_bloc.dart';
import '../models/product.dart';

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Shop'),
        actions: [
          // Cart badge
          JuiceBuilder<CartBloc>(
            groups: const {'cart:badge'},
            builder: (context, cartBloc, status) {
              final count = cartBloc.state.itemCount;
              return IconButton(
                onPressed: () {
                  final routingBloc = BlocScope.get<RoutingBloc>();
                  routingBloc.navigate('/cart');
                },
                icon: Badge(
                  isLabelVisible: count > 0,
                  label: Text('$count'),
                  child: const Icon(Icons.shopping_cart_outlined),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search products...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
              ),
              onSubmitted: (query) {
                final productsBloc = BlocScope.get<ProductsBloc>();
                productsBloc.send(SearchProductsEvent(query: query));
              },
            ),
          ),

          // Category chips
          JuiceBuilder<ProductsBloc>(
            groups: const {'products:list'},
            builder: (context, productsBloc, status) {
              final categories = productsBloc.state.categories;
              if (categories.isEmpty) return const SizedBox.shrink();

              return SizedBox(
                height: 48,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  scrollDirection: Axis.horizontal,
                  itemCount: categories.length + 1,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return FilterChip(
                        label: const Text('All'),
                        selected:
                            productsBloc.state.activeCategory == null,
                        onSelected: (_) =>
                            productsBloc.send(LoadProductsEvent()),
                      );
                    }
                    final cat = categories[index - 1];
                    return FilterChip(
                      label: Text(cat.name),
                      selected:
                          productsBloc.state.activeCategory == cat.slug,
                      onSelected: (_) => productsBloc
                          .send(LoadProductsEvent(category: cat.slug)),
                    );
                  },
                ),
              );
            },
          ),
          const SizedBox(height: 8),

          // Product grid
          Expanded(
            child: JuiceBuilder<ProductsBloc>(
              groups: const {'products:list'},
              builder: (context, productsBloc, status) {
                final state = productsBloc.state;

                if (state.products.isEmpty && state.isLoadingMore) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (state.products.isEmpty) {
                  return const Center(child: Text('No products found'));
                }

                return RefreshIndicator(
                  onRefresh: () async {
                    productsBloc.send(LoadProductsEvent(
                        category: state.activeCategory));
                    await Future.delayed(
                        const Duration(milliseconds: 500));
                  },
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (notification) {
                      if (notification is ScrollEndNotification &&
                          notification.metrics.extentAfter < 200) {
                        productsBloc.send(LoadMoreProductsEvent());
                      }
                      return false;
                    },
                    child: GridView.builder(
                      padding: const EdgeInsets.all(12),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        childAspectRatio: 0.7,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                      itemCount: state.products.length +
                          (state.isLoadingMore ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == state.products.length) {
                          return const Center(
                              child: CircularProgressIndicator());
                        }
                        return _ProductCard(
                          product: state.products[index],
                          onTap: () {
                            productsBloc.send(LoadProductDetailEvent(
                                productId: state.products[index].id));
                            final routingBloc =
                                BlocScope.get<RoutingBloc>();
                            routingBloc.navigate(
                                '/products/${state.products[index].id}');
                          },
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;

  const _ProductCard({required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: Container(
                width: double.infinity,
                color: Colors.grey[100],
                child: product.thumbnail.isNotEmpty
                    ? Image.network(
                        product.thumbnail,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(
                            Icons.image_not_supported,
                            size: 48),
                      )
                    : const Icon(Icons.shopping_bag, size: 48),
              ),
            ),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        Text(
                          '\$${product.discountedPrice.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        if (product.discountPercentage > 0) ...[
                          const SizedBox(width: 4),
                          Text(
                            '\$${product.price.toStringAsFixed(0)}',
                            style: const TextStyle(
                              decoration: TextDecoration.lineThrough,
                              fontSize: 11,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ],
                    ),
                    Row(
                      children: [
                        const Icon(Icons.star, size: 14, color: Colors.amber),
                        const SizedBox(width: 2),
                        Text(
                          product.rating.toStringAsFixed(1),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
