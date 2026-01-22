import 'package:juice/juice.dart';

// Product state
class ProductState extends BlocState {
  final List<Product> products;
  final Product? selectedProduct;

  const ProductState({
    this.products = const [],
    this.selectedProduct,
  });

  ProductState copyWith({
    List<Product>? products,
    Product? selectedProduct,
  }) {
    return ProductState(
      products: products ?? this.products,
      selectedProduct: selectedProduct ?? this.selectedProduct,
    );
  }
}

class Product {
  final String id;
  final String name;
  final double price;

  const Product({
    required this.id,
    required this.name,
    required this.price,
  });
}

// Events
class LoadProductsEvent extends EventBase {}

class SelectProductEvent extends EventBase {
  final Product product;
  SelectProductEvent(this.product);
}

// Use cases
class LoadProductsUseCase extends BlocUseCase<ProductBloc, LoadProductsEvent> {
  @override
  Future<void> execute(LoadProductsEvent event) async {
    emitWaiting();

    // Simulate API call
    await Future.delayed(const Duration(milliseconds: 300));

    final products = [
      const Product(id: '1', name: 'Flutter Widget', price: 29.99),
      const Product(id: '2', name: 'Dart Package', price: 49.99),
      const Product(id: '3', name: 'State Manager', price: 99.99),
    ];

    emitUpdate(
      newState: bloc.state.copyWith(products: products),
    );
  }
}

/// This use case demonstrates loose coupling via Aviator.
///
/// Instead of directly calling `routingBloc.navigate('/product/123')`,
/// it uses `emitUpdate(aviatorName: 'viewProduct')` which triggers
/// the registered aviator. The use case doesn't need to know about
/// routes or the routing system at all.
class SelectProductUseCase extends BlocUseCase<ProductBloc, SelectProductEvent> {
  @override
  Future<void> execute(SelectProductEvent event) async {
    emitUpdate(
      newState: bloc.state.copyWith(selectedProduct: event.product),
      // Navigate via aviator - loose coupling!
      // The use case doesn't know about routes, just intent
      aviatorName: 'viewProduct',
      aviatorArgs: {'productId': event.product.id},
    );
  }
}

// Bloc
class ProductBloc extends JuiceBloc<ProductState> {
  ProductBloc()
      : super(
          const ProductState(),
          [
            () => UseCaseBuilder(
                  typeOfEvent: LoadProductsEvent,
                  useCaseGenerator: () => LoadProductsUseCase(),
                  initialEventBuilder: () => LoadProductsEvent(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: SelectProductEvent,
                  useCaseGenerator: () => SelectProductUseCase(),
                ),
          ],
          [
            // Register aviator that maps intent to navigation
            () => Aviator(
                  name: 'viewProduct',
                  navigateWhere: (args) {
                    final productId = args['productId'] as String?;
                    if (productId != null) {
                      // This is where we connect to the routing system
                      // The use case doesn't need to know about this
                      print('[Aviator] viewProduct -> /product/$productId');
                    }
                  },
                ),
          ],
        );

  void selectProduct(Product product) => send(SelectProductEvent(product));
}
