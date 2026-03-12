import 'package:juice/juice.dart';
import '../models/cart_item.dart';

class CartState extends BlocState {
  final List<CartItem> items;
  final bool isCheckingOut;
  final bool orderPlaced;

  const CartState({
    this.items = const [],
    this.isCheckingOut = false,
    this.orderPlaced = false,
  });

  double get total =>
      items.fold(0, (sum, i) => sum + i.price * i.quantity);

  int get itemCount =>
      items.fold(0, (sum, i) => sum + i.quantity);

  CartState copyWith({
    List<CartItem>? items,
    bool? isCheckingOut,
    bool? orderPlaced,
  }) {
    return CartState(
      items: items ?? this.items,
      isCheckingOut: isCheckingOut ?? this.isCheckingOut,
      orderPlaced: orderPlaced ?? this.orderPlaced,
    );
  }
}
