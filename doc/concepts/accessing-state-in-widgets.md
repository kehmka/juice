# Accessing State in Juice Widgets

When working with Juice widgets, always access state through the bloc directly using `bloc.state`, not through the StreamStatus object. This is crucial for several reasons:

1. **Type Safety**
   - The StreamStatus's state type may not be what you expect, especially in multi-bloc scenarios
   - Accessing through bloc.state ensures compile-time type checking
   - IDE autocomplete works reliably with bloc.state

```dart
// ❌ Type safety issues with status.state
class UnsafeWidget extends StatelessJuiceWidget2<OrderBloc, PaymentBloc> {
  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    // status.state could be OrderState OR PaymentState
    // No type safety or autocomplete help!
    return Text(status.state.total.toString());  // Dangerous!
  }
}

// ✅ Type-safe access with bloc.state
class SafeWidget extends StatelessJuiceWidget2<OrderBloc, PaymentBloc> {
  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    // Compiler ensures type safety
    // IDE provides proper autocomplete
    return Text(bloc1.state.total.toString());  // Safe!
  }
}
```

2. **Consistency**
   - StreamStatus could come from any bloc in multi-bloc widgets
   - State accessed through bloc.state is always from the expected bloc
   - Makes code behavior predictable and reliable

```dart
class DashboardWidget extends StatelessJuiceWidget2<UserBloc, DataBloc> {
  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    // ❌ Inconsistent - which bloc's status is this?
    if (status is WaitingStatus) {
      // Is user data or dashboard data loading?
      return LoadingSpinner();
    }

    // ✅ Clear and consistent state access
    return Column(
      children: [
        UserPanel(
          userData: bloc1.state.userData,  // Clearly from UserBloc
          isLoading: bloc1.currentStatus is WaitingStatus,
        ),
        DataView(
          data: bloc2.state.dashboardData,  // Clearly from DataBloc
          isLoading: bloc2.currentStatus is WaitingStatus,
        ),
      ],
    );
  }
}
```

3. **Code Clarity**
   - Always clear which bloc's state you're accessing
   - Makes code more readable and maintainable
   - Easier to understand data flow

```dart
class OrderWidget extends StatelessJuiceWidget3<
    OrderBloc,
    CustomerBloc,
    InventoryBloc> {
  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    // ❌ Unclear state access
    // status.state.items - which bloc owns this?
    
    // ✅ Clear state ownership
    return OrderForm(
      orderDetails: bloc1.state.orderDetails,  // Clearly from OrderBloc
      customer: bloc2.state.customerInfo,      // Clearly from CustomerBloc
      inventory: bloc3.state.availableItems,   // Clearly from InventoryBloc
      // Use status only for UI state decisions
      isProcessing: status is WaitingStatus,
    );
  }
}
```

### Best Practice Summary:

```dart
class BestPracticeWidget extends StatelessJuiceWidget2<ProfileBloc, SettingsBloc> {
  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    // ✅ GOOD: Clear state access
    final profile = bloc1.state.profile;      // Type-safe
    final settings = bloc2.state.settings;    // Consistent
    
    return Column(
      children: [
        ProfileView(profile: profile),        // Clear ownership
        SettingsView(settings: settings),     // Clear ownership
        // Use status only for UI state
        if (status is WaitingStatus)
          LoadingOverlay(),
      ],
    );
  }
}
```

Remember:
- Use `bloc.state` for accessing data
- Use StreamStatus for UI state decisions (loading, error states, etc.)
- Keep state access clear and type-safe
- Be explicit about which bloc owns what data