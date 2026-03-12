import 'package:juice/juice.dart';
import 'package:juice_network/juice_network.dart';
import '../products_bloc.dart';
import '../products_events.dart';
import '../../models/product.dart';

class LoadProductDetailUseCase
    extends UseCase<ProductsBloc, LoadProductDetailEvent> {
  @override
  Future<void> execute(LoadProductDetailEvent event) async {
    // Check if we already have this product in the list
    final existing =
        bloc.state.products.where((p) => p.id == event.productId).firstOrNull;
    if (existing != null) {
      emitUpdate(
        newState: bloc.state.copyWith(selectedProduct: existing),
      );
      return;
    }

    emitWaiting();

    try {
      await bloc.fetchBloc.send(GetEvent(
        url: 'https://dummyjson.com/products/${event.productId}',
        cachePolicy: CachePolicy.cacheFirst,
        ttl: const Duration(minutes: 10),
        decode: (raw) {
          final product = Product.fromJson(raw as Map<String, dynamic>);
          emitUpdate(
            newState: bloc.state.copyWith(selectedProduct: product),
          );
          return product;
        },
      ));
    } catch (e) {
      emitFailure(error: e);
    }
  }
}
