import 'dart:convert';
import 'package:juice/juice.dart';
import 'package:juice_storage/juice_storage.dart';
import '../cart_bloc.dart';
import '../cart_events.dart';
import '../../models/cart_item.dart';

class RemoveFromCartUseCase extends UseCase<CartBloc, RemoveFromCartEvent> {
  @override
  Future<void> execute(RemoveFromCartEvent event) async {
    final items =
        bloc.state.items.where((i) => i.productId != event.productId).toList();
    emitUpdate(newState: bloc.state.copyWith(items: items));
    await _persistCart(items);
  }

  Future<void> _persistCart(List<CartItem> items) async {
    final storageBloc = BlocScope.get<StorageBloc>();
    final json = jsonEncode(items.map((i) => i.toJson()).toList());
    await storageBloc.hiveWrite<String>('cart', 'items', json);
  }
}

class UpdateCartQuantityUseCase
    extends UseCase<CartBloc, UpdateCartQuantityEvent> {
  @override
  Future<void> execute(UpdateCartQuantityEvent event) async {
    if (event.quantity <= 0) {
      bloc.send(RemoveFromCartEvent(productId: event.productId));
      return;
    }

    final items = bloc.state.items.map((i) {
      if (i.productId == event.productId) {
        return i.copyWith(quantity: event.quantity);
      }
      return i;
    }).toList();

    emitUpdate(newState: bloc.state.copyWith(items: items));

    final storageBloc = BlocScope.get<StorageBloc>();
    final json = jsonEncode(items.map((i) => i.toJson()).toList());
    await storageBloc.hiveWrite<String>('cart', 'items', json);
  }
}
