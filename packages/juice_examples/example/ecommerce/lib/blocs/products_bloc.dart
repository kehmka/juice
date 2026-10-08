import 'package:juice/juice.dart';
import 'package:juice_network/juice_network.dart';
import 'products_state.dart';
import 'products_events.dart';
import 'use_cases/load_products_use_case.dart';
import 'use_cases/search_products_use_case.dart';
import 'use_cases/load_product_detail_use_case.dart';

class ProductsBloc extends JuiceBloc<ProductsState> {
  final FetchBloc fetchBloc;

  ProductsBloc({required this.fetchBloc})
      : super(
          const ProductsState(),
          [
            () => UseCaseBuilder(
                  typeOfEvent: LoadProductsEvent,
                  useCaseGenerator: () => LoadProductsUseCase(),
                  initialEventBuilder: () => LoadProductsEvent(),
                  concurrency: EventConcurrency.sequential,
                ),
            () => UseCaseBuilder(
                  typeOfEvent: LoadCategoriesEvent,
                  useCaseGenerator: () => LoadCategoriesUseCase(),
                  initialEventBuilder: () => LoadCategoriesEvent(),
                  concurrency: EventConcurrency.droppable,
                ),
            () => UseCaseBuilder(
                  typeOfEvent: LoadMoreProductsEvent,
                  useCaseGenerator: () => LoadMoreProductsUseCase(),
                  concurrency: EventConcurrency.droppable,
                ),
            () => UseCaseBuilder(
                  typeOfEvent: SearchProductsEvent,
                  useCaseGenerator: () => SearchProductsUseCase(),
                  concurrency: EventConcurrency.sequential,
                ),
            () => UseCaseBuilder(
                  typeOfEvent: LoadProductDetailEvent,
                  useCaseGenerator: () => LoadProductDetailUseCase(),
                  concurrency: EventConcurrency.sequential,
                ),
          ],
        );
}
