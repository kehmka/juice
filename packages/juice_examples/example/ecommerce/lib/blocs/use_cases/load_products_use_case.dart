import 'package:juice/juice.dart';
import 'package:juice_network/juice_network.dart';
import '../products_bloc.dart';
import '../products_events.dart';
import '../../models/product.dart';
import '../../models/category.dart';

class LoadProductsUseCase extends UseCase<ProductsBloc, LoadProductsEvent> {
  @override
  Future<void> execute(LoadProductsEvent event) async {
    emitUpdate(
      newState: bloc.state.copyWith(
        isLoadingMore: true,
        activeCategory: event.category,
        clearActiveCategory: event.category == null,
        currentPage: 0,
      ),
    );

    try {
      final url = event.category != null
          ? 'https://dummyjson.com/products/category/${event.category}'
          : 'https://dummyjson.com/products';

      await bloc.fetchBloc.send(GetEvent(
        url: url,
        queryParams: {'limit': 20, 'skip': 0},
        cachePolicy: CachePolicy.staleWhileRevalidate,
        ttl: const Duration(minutes: 5),
        decode: (raw) {
          final data = raw as Map<String, dynamic>;
          final list = data['products'] as List<dynamic>;
          final total = data['total'] as int;
          final products = list
              .map((e) => Product.fromJson(e as Map<String, dynamic>))
              .toList();
          emitUpdate(
            newState: bloc.state.copyWith(
              products: products,
              currentPage: 0,
              hasReachedEnd: products.length >= total,
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

class LoadCategoriesUseCase
    extends UseCase<ProductsBloc, LoadCategoriesEvent> {
  @override
  Future<void> execute(LoadCategoriesEvent event) async {
    try {
      await bloc.fetchBloc.send(GetEvent(
        url: 'https://dummyjson.com/products/categories',
        cachePolicy: CachePolicy.cacheFirst,
        ttl: const Duration(hours: 1),
        decode: (raw) {
          final list = raw as List<dynamic>;
          final categories =
              list.map((e) => ProductCategory.fromJson(e)).toList();
          emitUpdate(
            newState: bloc.state.copyWith(categories: categories),
          );
          return categories;
        },
      ));
    } catch (_) {
      // Silent fail — categories are non-critical
    }
  }
}

class LoadMoreProductsUseCase
    extends UseCase<ProductsBloc, LoadMoreProductsEvent> {
  @override
  Future<void> execute(LoadMoreProductsEvent event) async {
    if (bloc.state.hasReachedEnd || bloc.state.isLoadingMore) return;

    final nextPage = bloc.state.currentPage + 1;
    final skip = nextPage * 20;
    emitUpdate(newState: bloc.state.copyWith(isLoadingMore: true));

    try {
      final url = bloc.state.activeCategory != null
          ? 'https://dummyjson.com/products/category/${bloc.state.activeCategory}'
          : 'https://dummyjson.com/products';

      await bloc.fetchBloc.send(GetEvent(
        url: url,
        queryParams: {'limit': 20, 'skip': skip},
        cachePolicy: CachePolicy.networkFirst,
        ttl: const Duration(minutes: 5),
        decode: (raw) {
          final data = raw as Map<String, dynamic>;
          final list = data['products'] as List<dynamic>;
          final total = data['total'] as int;
          final newProducts = list
              .map((e) => Product.fromJson(e as Map<String, dynamic>))
              .toList();
          final allProducts = [...bloc.state.products, ...newProducts];
          emitUpdate(
            newState: bloc.state.copyWith(
              products: allProducts,
              currentPage: nextPage,
              hasReachedEnd: allProducts.length >= total,
              isLoadingMore: false,
            ),
          );
          return newProducts;
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
