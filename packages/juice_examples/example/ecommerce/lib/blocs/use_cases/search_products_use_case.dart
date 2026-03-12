import 'package:juice/juice.dart';
import 'package:juice_network/juice_network.dart';
import '../products_bloc.dart';
import '../products_events.dart';
import '../../models/product.dart';

class SearchProductsUseCase
    extends UseCase<ProductsBloc, SearchProductsEvent> {
  @override
  Future<void> execute(SearchProductsEvent event) async {
    if (event.query.isEmpty) {
      // Reset to full product list
      bloc.send(LoadProductsEvent());
      return;
    }

    emitUpdate(
      newState: bloc.state.copyWith(
        searchQuery: event.query,
        isLoadingMore: true,
        clearActiveCategory: true,
      ),
    );

    try {
      await bloc.fetchBloc.send(GetEvent(
        url: 'https://dummyjson.com/products/search',
        queryParams: {'q': event.query},
        cachePolicy: CachePolicy.networkFirst,
        ttl: const Duration(minutes: 2),
        decode: (raw) {
          final data = raw as Map<String, dynamic>;
          final list = data['products'] as List<dynamic>;
          final products = list
              .map((e) => Product.fromJson(e as Map<String, dynamic>))
              .toList();
          emitUpdate(
            newState: bloc.state.copyWith(
              products: products,
              hasReachedEnd: true,
              isLoadingMore: false,
            ),
          );
          return products;
        },
      ));
    } catch (e) {
      emitFailure(
        newState: bloc.state.copyWith(isLoadingMore: false),
        error: e,
      );
    }
  }
}
