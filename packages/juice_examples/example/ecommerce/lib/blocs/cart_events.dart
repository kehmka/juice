import 'package:juice/juice.dart';
import '../models/product.dart';

class AddToCartEvent extends EventBase {
  final Product product;
  AddToCartEvent({required this.product})
      : super(groupsToRebuild: {'cart:items', 'cart:badge'});
}

class RemoveFromCartEvent extends EventBase {
  final int productId;
  RemoveFromCartEvent({required this.productId})
      : super(groupsToRebuild: {'cart:items', 'cart:badge'});
}

class UpdateCartQuantityEvent extends EventBase {
  final int productId;
  final int quantity;
  UpdateCartQuantityEvent({required this.productId, required this.quantity})
      : super(groupsToRebuild: {'cart:items', 'cart:badge'});
}

class CheckoutEvent extends EventBase {
  CheckoutEvent() : super(groupsToRebuild: {'cart:items', 'cart:badge'});
}

class LoadCartEvent extends EventBase {
  LoadCartEvent() : super(groupsToRebuild: {'cart:items', 'cart:badge'});
}
