# Use Cases in Juice

Use cases are the building blocks of business logic in Juice. Each use case represents a single operation that can be performed in your application.

## Basic Use Case Pattern

### Creating a Use Case

Every use case extends `BlocUseCase` with the bloc type and event type:

```dart
class SendMessageUseCase extends BlocUseCase<ChatBloc, SendMessageEvent> {
  @override
  Future<void> execute(SendMessageEvent event) async {
    emitWaiting(groupsToRebuild: {"chat_status"});
    
    try {
      await chatService.send(event.message);
      emitUpdate(
        newState: bloc.state.copyWith(
          messages: [...bloc.state.messages, event.message]
        ),
        groupsToRebuild: {"chat_messages", "chat_status"}
      );
    } catch (e) {
      emitFailure(groupsToRebuild: {"chat_status"});
    }
  }
}
```

### Registering in the Bloc

Use cases are registered in the bloc constructor using `UseCaseBuilder`:

```dart
class ChatBloc extends JuiceBloc<ChatState> {
  ChatBloc(this._chatService) : super(
    ChatState.initial(),
    [
      // Basic registration
      () => UseCaseBuilder(
        typeOfEvent: SendMessageEvent,
        useCaseGenerator: () => SendMessageUseCase(),
      ),
      
      // With initial event
      () => UseCaseBuilder(
        typeOfEvent: LoadMessagesEvent,
        useCaseGenerator: () => LoadMessagesUseCase(),
        initialEventBuilder: () => LoadMessagesEvent(),
      ),
    ],
    [], // Aviators
  );

  final ChatService _chatService;
}
```

### Basic Use Case Types

1. **Update Use Case** - Simple state updates:
```dart
class UpdateProfileUseCase extends BlocUseCase<ProfileBloc, UpdateProfileEvent> {
  @override
  Future<void> execute(UpdateProfileEvent event) async {
    emitUpdate(
      newState: bloc.state.copyWith(
        name: event.name,
        email: event.email
      ),
      groupsToRebuild: {"profile"}
    );
  }
}
```

2. **Loading Use Case** - Data fetching:
```dart
class LoadOrdersUseCase extends BlocUseCase<OrderBloc, LoadOrdersEvent> {
  @override
  Future<void> execute(LoadOrdersEvent event) async {
    emitWaiting(groupsToRebuild: {"orders_list"});
    
    try {
      final orders = await orderService.fetchOrders();
      emitUpdate(
        newState: bloc.state.copyWith(orders: orders),
        groupsToRebuild: {"orders_list", "orders_count"}
      );
    } catch (e) {
      emitFailure(groupsToRebuild: {"orders_list"});
    }
  }
}
```

3. **Operation Use Case** - Complex operations:
```dart
class ProcessPaymentUseCase extends BlocUseCase<PaymentBloc, ProcessPaymentEvent> {
  @override
  Future<void> execute(ProcessPaymentEvent event) async {
    emitWaiting(groupsToRebuild: {"payment_status"});
    
    try {
      // Process payment
      final result = await paymentService.process(event.payment);
      
      // Update order status
      await orderService.updateStatus(event.orderId, OrderStatus.paid);
      
      // Navigate on success
      emitUpdate(
        newState: bloc.state.copyWith(
          paymentResult: result,
          orderStatus: OrderStatus.paid
        ),
        groupsToRebuild: {"payment_status", "order_status"},
        aviatorName: 'orderComplete',
        aviatorArgs: {'orderId': event.orderId}
      );
    } catch (e) {
      emitFailure(
        newState: bloc.state.copyWith(error: e.toString()),
        groupsToRebuild: {"payment_status"}
      );
    }
  }
}
```

## Advanced Use Cases

### Stateful Use Cases

When you need to maintain state across event handling:

```dart
class WebSocketUseCase extends StatefulUseCaseBuilder<ChatBloc, ConnectEvent> {
  WebSocket? _socket;
  StreamSubscription? _subscription;
  
  @override
  Future<void> execute(ConnectEvent event) async {
    _socket = await WebSocket.connect(event.url);
    
    _subscription = _socket?.listen(
      (message) {
        bloc.send(MessageReceivedEvent(message));
      },
      onError: (error) {
        bloc.send(ConnectionErrorEvent(error));
      }
    );
  }
  
  @override
  Future<void> close() async {
    await _subscription?.cancel();
    await _socket?.close();
    super.close();
  }
}
```

### Cross-Bloc Communication

For connecting multiple blocs, use `StateRelay` or `StatusRelay`:

```dart
// StateRelay - Simple state-to-event transformation
final authToProfileRelay = StateRelay<AuthBloc, ProfileBloc, AuthState>(
  toEvent: (state) => state.isAuthenticated
      ? LoadProfileEvent(userId: state.userId!)
      : ClearProfileEvent(),
  when: (state) => state.userId != null,
);

// StatusRelay - When you need to handle waiting/error states
final relay = StatusRelay<AuthBloc, ProfileBloc, AuthState>(
  toEvent: (status) => status.when(
    updating: (state, _, __) => state.isAuthenticated
        ? LoadProfileEvent(userId: state.userId!)
        : ClearProfileEvent(),
    waiting: (_, __, ___) => ProfileLoadingEvent(),
    failure: (_, __, ___) => ClearProfileEvent(),
    canceling: (_, __, ___) => ClearProfileEvent(),
  ),
);

// Don't forget to close when done
await authToProfileRelay.close();
```

See [Cross-Bloc Communication](relay-use-cases.md) for more details.

### Cancellable Use Cases

For long-running operations that can be cancelled:

```dart
class UploadFileUseCase extends BlocUseCase<UploadBloc, UploadFileEvent> {
  @override
  Future<void> execute(UploadFileEvent event) async {
    emitWaiting(groupsToRebuild: {"upload_status"});
    
    try {
      if (event is CancellableEvent && event.isCancelled) {
        emitCancel(groupsToRebuild: {"upload_status"});
        return;
      }

      await uploadService.upload(
        event.file,
        onProgress: (progress) {
          // Check cancellation during upload
          if (event is CancellableEvent && event.isCancelled) {
            throw CancelledException();
          }
          
          emitUpdate(
            newState: bloc.state.copyWith(progress: progress),
            groupsToRebuild: {"upload_progress"}
          );
        }
      );
      
      emitUpdate(
        newState: bloc.state.copyWith(isComplete: true),
        groupsToRebuild: {"upload_status", "upload_progress"}
      );
    } on CancelledException {
      emitCancel(groupsToRebuild: {"upload_status"});
    } catch (e) {
      emitFailure(groupsToRebuild: {"upload_status"});
    }
  }
}
```

### Composite Use Cases

For coordinating multiple operations:

```dart
class CheckoutUseCase extends BlocUseCase<CheckoutBloc, CheckoutEvent> {
  @override
  Future<void> execute(CheckoutEvent event) async {
    emitWaiting(groupsToRebuild: {"checkout_status"});
    
    try {
      // Validate cart
      final cart = await validateCart();
      if (!cart.isValid) {
        throw ValidationException('Invalid cart');
      }
      
      // Process payment
      final payment = await processPayment(event.paymentDetails);
      if (!payment.isSuccessful) {
        throw PaymentException('Payment failed');
      }
      
      // Create order
      final order = await createOrder(cart, payment);
      
      // Send confirmation
      await sendConfirmation(order);
      
      // Update state and navigate
      emitUpdate(
        newState: bloc.state.copyWith(
          order: order,
          status: CheckoutStatus.complete
        ),
        groupsToRebuild: {"checkout_status", "order_details"},
        aviatorName: 'orderConfirmation',
        aviatorArgs: {'orderId': order.id}
      );
    } catch (e) {
      emitFailure(
        newState: bloc.state.copyWith(error: e.toString()),
        groupsToRebuild: {"checkout_status"}
      );
    }
  }
}
```

## Best Practices

1. **Single Responsibility**
   - Each use case should do one thing well
   - Break complex operations into multiple use cases
   - Use composition for complex flows

2. **Error Handling**
   - Always handle errors appropriately
   - Use specific error types
   - Provide meaningful error messages

3. **State Updates**
   - Be specific with groupsToRebuild
   - Update only what's necessary
   - Consider derived state impacts

4. **Resource Management**
   - Clean up resources in close()
   - Cancel subscriptions properly
   - Handle timeouts appropriately

5. **Testing**
   - Make use cases easily testable
   - Mock dependencies properly
   - Test error cases

## Advanced Patterns

### Chaining Use Cases
```dart
class SignUpUseCase extends BlocUseCase<AuthBloc, SignUpEvent> {
  @override
  Future<void> execute(SignUpEvent event) async {
    // Chain multiple operations
    await validateEmail();
    await createUser();
    await sendVerification();
    await syncPreferences();
  }
  
  Future<void> validateEmail() async {
    emitWaiting(groupsToRebuild: {"signup_status"});
    // Validation logic
  }
  
  Future<void> createUser() async {
    emitWaiting(groupsToRebuild: {"signup_status"});
    // User creation logic
  }
  
  // Additional methods...
}
```

### Use Case Coordination
```dart
class OrderCoordinatorUseCase extends BlocUseCase<OrderBloc, CreateOrderEvent> {
  @override
  Future<void> execute(CreateOrderEvent event) async {
    // Coordinate multiple blocs
    final cartBloc = resolver.resolve<CartBloc>();
    final paymentBloc = resolver.resolve<PaymentBloc>();
    final inventoryBloc = resolver.resolve<InventoryBloc>();
    
    // Execute coordinated operations
    await validateInventory(inventoryBloc);
    await processPayment(paymentBloc);
    await createOrder();
    await clearCart(cartBloc);
  }
}
```

Remember: Use cases are the heart of your application's business logic. Take time to design them well and keep them focused and maintainable.