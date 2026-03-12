import 'package:juice/juice.dart';
import 'cart_state.dart';
import 'cart_events.dart';
import 'use_cases/add_to_cart_use_case.dart';
import 'use_cases/remove_from_cart_use_case.dart';
import 'use_cases/checkout_use_case.dart';

class CartBloc extends JuiceBloc<CartState> {
  CartBloc()
      : super(
          const CartState(),
          [
            () => UseCaseBuilder(
                  typeOfEvent: LoadCartEvent,
                  useCaseGenerator: () => LoadCartUseCase(),
                  initialEventBuilder: () => LoadCartEvent(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: AddToCartEvent,
                  useCaseGenerator: () => AddToCartUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: RemoveFromCartEvent,
                  useCaseGenerator: () => RemoveFromCartUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: UpdateCartQuantityEvent,
                  useCaseGenerator: () => UpdateCartQuantityUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: CheckoutEvent,
                  useCaseGenerator: () => CheckoutUseCase(),
                ),
          ],
        );
}
