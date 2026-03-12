import 'dart:convert';
import 'package:juice/juice.dart';
import 'package:juice_storage/juice_storage.dart';
import '../cart_bloc.dart';
import '../cart_events.dart';
import '../../models/cart_item.dart';

class CheckoutUseCase extends UseCase<CartBloc, CheckoutEvent> {
  @override
  Future<void> execute(CheckoutEvent event) async {
    emitWaiting(newState: bloc.state.copyWith(isCheckingOut: true));

    // Simulate payment processing
    await Future.delayed(const Duration(seconds: 2));

    // Clear cart
    final storageBloc = BlocScope.get<StorageBloc>();
    await storageBloc.hiveDelete('cart', 'items');

    emitUpdate(
      newState: bloc.state.copyWith(
        items: [],
        isCheckingOut: false,
        orderPlaced: true,
      ),
    );
  }
}

class LoadCartUseCase extends UseCase<CartBloc, LoadCartEvent> {
  @override
  Future<void> execute(LoadCartEvent event) async {
    final storageBloc = BlocScope.get<StorageBloc>();
    final raw = await storageBloc.hiveRead<String>('cart', 'items');

    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        final items = list
            .map((e) => CartItem.fromJson(e as Map<String, dynamic>))
            .toList();
        emitUpdate(newState: bloc.state.copyWith(items: items));
      } catch (_) {
        // Corrupted cart data — start fresh
      }
    }
  }
}
