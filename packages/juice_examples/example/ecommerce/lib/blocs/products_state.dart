import 'package:juice/juice.dart';
import '../models/product.dart';
import '../models/category.dart';

class ProductsState extends BlocState {
  final List<Product> products;
  final List<ProductCategory> categories;
  final String? activeCategory;
  final String searchQuery;
  final Product? selectedProduct;
  final bool isLoadingMore;
  final bool hasReachedEnd;
  final int currentPage;

  const ProductsState({
    this.products = const [],
    this.categories = const [],
    this.activeCategory,
    this.searchQuery = '',
    this.selectedProduct,
    this.isLoadingMore = false,
    this.hasReachedEnd = false,
    this.currentPage = 0,
  });

  ProductsState copyWith({
    List<Product>? products,
    List<ProductCategory>? categories,
    String? activeCategory,
    String? searchQuery,
    Product? selectedProduct,
    bool? isLoadingMore,
    bool? hasReachedEnd,
    int? currentPage,
    bool clearActiveCategory = false,
    bool clearSelectedProduct = false,
  }) {
    return ProductsState(
      products: products ?? this.products,
      categories: categories ?? this.categories,
      activeCategory:
          clearActiveCategory ? null : (activeCategory ?? this.activeCategory),
      searchQuery: searchQuery ?? this.searchQuery,
      selectedProduct: clearSelectedProduct
          ? null
          : (selectedProduct ?? this.selectedProduct),
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasReachedEnd: hasReachedEnd ?? this.hasReachedEnd,
      currentPage: currentPage ?? this.currentPage,
    );
  }
}
