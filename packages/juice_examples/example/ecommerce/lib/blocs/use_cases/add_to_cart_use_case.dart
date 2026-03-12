import 'dart:convert';
import 'package:juice/juice.dart';
import 'package:juice_storage/juice_storage.dart';
import '../cart_bloc.dart';
import '../cart_events.dart';
import '../../models/cart_item.dart';

class AddToCartUseCase extends UseCase<CartBloc, AddToCartEvent> {
  @override
  Future<void> execute(AddToCartEvent event) async {
    final items = List<CartItem>.from(bloc.state.items);
    final existingIndex =
        items.indexWhere((i) => i.productId == event.product.id);

    if (existingIndex >= 0) {
      items[existingIndex] = items[existingIndex]
          .copyWith(quantity: items[existingIndex].quantity + 1);
    } else {
      items.add(CartItem(
        productId: event.product.id,
        title: event.product.title,
        price: event.product.discountedPrice,
        thumbnail: event.product.thumbnail,
      ));
    }

    emitUpdate(newState: bloc.state.copyWith(items: items));
    await _persistCart(items);
  }

  Future<void> _persistCart(List<CartItem> items) async {
    final storageBloc = BlocScope.get<StorageBloc>();
    final json = jsonEncode(items.map((i) => i.toJson()).toList());
    await storageBloc.hiveWrite<String>('cart', 'items', json);
  }
}
