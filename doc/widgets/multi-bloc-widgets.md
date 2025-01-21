# Working with Multi-Bloc Widgets in Juice

Multi-bloc widgets allow you to build UI components that respond to state changes from multiple blocs simultaneously. This guide explains how to use them effectively and avoid common pitfalls.

## When to Use Multi-Bloc Widgets

Use multi-bloc widgets when you have UI components that need to:

1. **Show Combined State**: Display information that comes from multiple sources
   ```dart
   // Example: Order summary that needs both order and customer details
   class OrderSummary extends StatelessJuiceWidget2<OrderBloc, CustomerBloc> {
     @override
     Widget onBuild(BuildContext context, StreamStatus status) {
       return Column(
         children: [
           CustomerDetails(customer: bloc2.state.customer),  // From CustomerBloc
           OrderDetails(order: bloc1.state.order),          // From OrderBloc
         ],
       );
     }
   }
   ```

2. **Coordinate Actions**: Handle operations that affect multiple areas
   ```dart
   // Example: Shopping cart that affects both cart and inventory
   class AddToCartButton extends StatelessJuiceWidget2<CartBloc, InventoryBloc> {
     @override
     Widget onBuild(BuildContext context, StreamStatus status) {
       final inStock = bloc2.state.hasStock(item.id);
       final inCart = bloc1.state.contains(item.id);
       
       return ElevatedButton(
         onPressed: inStock && !inCart 
           ? () => bloc1.send(AddToCartEvent(item))
           : null,
         child: Text('Add to Cart'),
       );
     }
   }
   ```

3. **Cross-Feature Updates**: Handle changes that span multiple features
   ```dart
   // Example: Profile page that shows auth status and user data
   class ProfilePage extends StatelessJuiceWidget2<AuthBloc, ProfileBloc> {
     @override
     Widget onBuild(BuildContext context, StreamStatus status) {
       if (!bloc1.state.isAuthenticated) {
         return LoginPrompt();
       }
       
       return UserProfile(data: bloc2.state.profileData);
     }
   }
   ```

## Naming Convention and Access

Juice uses a simple numbered convention for multiple blocs:

```dart
class MyWidget extends StatelessJuiceWidget2<FirstBloc, SecondBloc> {
  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    // Access blocs as bloc1, bloc2
    final firstState = bloc1.state;   // FirstBloc's state
    final secondState = bloc2.state;  // SecondBloc's state
    
    return Column(
      children: [
        Text('First: ${bloc1.state.value}'),
        Text('Second: ${bloc2.state.value}'),
      ],
    );
  }
}
```

The numbering matches the order of the generic type parameters:
- First type parameter → `bloc1`
- Second type parameter → `bloc2`
- Third type parameter → `bloc3` (in StatelessJuiceWidget3)

## IMPORTANT: Never Access State Through StreamStatus

The most critical rule when working with multi-bloc widgets is to never access state through the StreamStatus parameter:

```dart
// ❌ WRONG: Don't access state through status
Widget onBuild(BuildContext context, StreamStatus status) {
  return Text('Value: ${status.state.value}');  // Which bloc's state is this?
}

// ✅ CORRECT: Access state through numbered blocs
Widget onBuild(BuildContext context, StreamStatus status) {
  return Text('Value: ${bloc1.state.value}');  // Clearly from bloc1
}
```

Why? Because:
1. The StreamStatus could be from any of the blocs
2. No type safety when accessing through status
3. Makes code harder to understand and maintain

## Handling StreamStatus Correctly

Use StreamStatus only for UI state decisions (loading, error states, etc):

```dart
@override
Widget onBuild(BuildContext context, StreamStatus status) {
  // Handle status for UI states
  if (status is WaitingStatus<OrderState>) {
    return LoadingSpinner();
  }
  
  if (status is FailureStatus) {
    return ErrorDisplay();
  }
  
  // Access actual state data through bloc properties
  return Column(
    children: [
      // Clear which state comes from where
      UserHeader(user: bloc1.state.user),
      OrderList(orders: bloc2.state.orders),
      if (bloc3.state.hasNotifications)
        NotificationBadge(),
    ],
  );
}
```

## Creating Multi-Bloc Widgets

Juice provides three variants of multi-bloc widgets:

### StatelessJuiceWidget2 (Two Blocs)
```dart
class OrderView extends StatelessJuiceWidget2<OrderBloc, CustomerBloc> {
  OrderView({super.key, super.groups = const {"order"}});
  
  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    return Column(
      children: [
        CustomerInfo(customer: bloc2.state.customer),
        OrderDetails(order: bloc1.state.order),
      ],
    );
  }
}
```

### StatelessJuiceWidget3 (Three Blocs)
```dart
class CheckoutView extends StatelessJuiceWidget3<
    CartBloc,
    PaymentBloc,
    InventoryBloc> {
  CheckoutView({super.key, super.groups = const {"checkout"}});
  
  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    return Column(
      children: [
        CartSummary(cart: bloc1.state.cart),
        PaymentForm(methods: bloc2.state.paymentMethods),
        StockStatus(inventory: bloc3.state.inventory),
      ],
    );
  }
}
```

### StatefulJuiceWidget Variants
For stateful widgets, use `JuiceWidgetState2` and `JuiceWidgetState3`:

```dart
class ComplexForm extends StatefulWidget {
  @override
  State<ComplexForm> createState() => ComplexFormState();
}

class ComplexFormState extends JuiceWidgetState2<FormBloc, ValidationBloc> {
  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    return Form(
      child: Column(
        children: [
          FormFields(data: bloc1.state.formData),
          ValidationErrors(errors: bloc2.state.errors),
        ],
      ),
    );
  }
}
```

## Best Practices

1. **Keep Widget Focus Clear**
   ```dart
   // Good: Clear purpose for using multiple blocs
   class OrderConfirmation extends StatelessJuiceWidget2<OrderBloc, PaymentBloc> {
     // Order status and payment status naturally go together
   }
   
   // Bad: Unclear why these blocs are combined
   class RandomWidget extends StatelessJuiceWidget2<SettingsBloc, WeatherBloc> {
     // These features probably shouldn't be combined
   }
   ```

2. **Use Typed State Access**
   ```dart
   // Good: Type-safe state access
   final orderState: OrderState = bloc1.state;
   final paymentState: PaymentState = bloc2.state;
   
   // Bad: Unsafe status.state access
   final state = status.state;  // Type unclear
   ```

3. **Group Related Updates**
   ```dart
   // Good: Related groups
   OrderView({super.groups = const {"order_details", "order_status"}});
   
   // Bad: Too broad
   OrderView({super.groups = const {"*"}});  // Rebuilds on everything
   ```

4. **Handle Loading States Appropriately**
   ```dart
   @override 
   Widget onBuild(BuildContext context, StreamStatus status) {
     // Show loading only when actually needed
     if (status is WaitingStatus<OrderState> && 
         bloc1.state.isEmpty && 
         bloc2.state.isEmpty) {
       return LoadingSpinner();
     }
     
     // Otherwise show content with available data
     return Content(
       data1: bloc1.state.data,
       data2: bloc2.state.data,
     );
   }
   ```

## Common Pitfalls to Avoid

1. **Don't Mix Unrelated Blocs**
   ```dart
   // Bad: Unrelated concerns
   class WeatherSettings extends StatelessJuiceWidget2<WeatherBloc, ThemeBloc>
   
   // Good: Split into focused widgets
   class WeatherDisplay extends StatelessJuiceWidget<WeatherBloc>
   class ThemeSettings extends StatelessJuiceWidget<ThemeBloc>
   ```

2. **Use Type-Safe StreamStatus Checks**
   ```dart
   // Bad: Generic status check
   if (status is WaitingStatus) {
     return LoadingSpinner();
   }
   
   // Good: Type-safe status check
   if (status is WaitingStatus<OrderState>) {
     return OrderLoadingSpinner();
   } else if (status is WaitingStatus<PaymentState>) {
     return PaymentLoadingSpinner();
   }
   
   // Complete example with all status types:
   @override
   Widget onBuild(BuildContext context, StreamStatus status) {
     return status.when(
       updating: (state, _, __) => OrderContent(state: bloc1.state),
       waiting: (state, _, __) {
         // Type-safe checks for specific bloc states
         if (status is WaitingStatus<OrderState>) {
           return OrderLoadingSpinner();
         } else if (status is WaitingStatus<PaymentState>) {
           return PaymentLoadingSpinner();
         }
         return GeneralLoadingSpinner();
       },
       failure: (state, _, __) {
         if (status is FailureStatus<OrderState>) {
           return OrderError(error: "Order failed");
         } else if (status is FailureStatus<PaymentState>) {
           return PaymentError(error: "Payment failed");
         }
         return GeneralError();
       },
       canceling: (state, _, __) => CancelledDisplay(),
     );
   }
   ```

3. **Don't Overuse Multi-Bloc Widgets**
   ```dart
   // Bad: Unnecessary complexity
   class SimpleCounter extends StatelessJuiceWidget2<CounterBloc, ThemeBloc>
   
   // Good: Split into focused widgets
   class Counter extends StatelessJuiceWidget<CounterBloc>
   ```

4. **Don't Forget Error Handling**
   ```dart
   // Bad: Missing error states
   Widget onBuild(BuildContext context, StreamStatus status) {
     return Content(/*...*/);
   }
   
   // Good: Handle errors
   Widget onBuild(BuildContext context, StreamStatus status) {
     if (status is FailureStatus<OrderState>) {
       return ErrorDisplay(
         error: status.error,
         // Still safe to access bloc state
         canRetry: bloc1.state.canRetry,
       );
     }
     return Content(/*...*/);
   }
   ```

Remember that multi-bloc widgets are a powerful tool but should be used judiciously. Always prefer simpler solutions when possible, and only combine blocs when there's a clear need for coordinated state management.