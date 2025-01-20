### Working with StreamStatus

StreamStatus helps manage different UI states (updating, waiting, error, canceling). For simple widgets, the `when` method works well:

```dart
// Simple widget using when pattern
@override
Widget onBuild(BuildContext context, StreamStatus status) {
  return status.when(
    updating: (_) => Text('Count: ${bloc.state.count}'),
    waiting: (_) => CircularProgressIndicator(),
    error: (_) => Text('Error occurred'),
    canceling: (_) => Text('Operation cancelled'),
  );
}
```

However, for complex UIs, there are better patterns:

#### Pattern 1: Status-Aware Component Methods

Break your UI into logical pieces and handle status per component:

```dart
class ComplexProfileWidget extends StatelessJuiceWidget<ProfileBloc> {
  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    return Column(
      children: [
        _buildHeader(context, status),
        _buildBody(context, status),
        _buildActions(context, status),
      ],
    );
  }

  Widget _buildHeader(BuildContext context, StreamStatus status) {
    final profile = bloc.state.profile;
    
    // Handle loading state inline where needed
    if (status is WaitingStatus) {
      return ShimmerLoading(child: ProfileHeaderPlaceholder());
    }
    
    return ProfileHeader(
      title: profile.name,
      subtitle: profile.email,
      // Disable actions during certain states
      enabled: status is! WaitingStatus && status is! CancelingStatus,
    );
  }

  Widget _buildBody(BuildContext context, StreamStatus status) {
    // Access state directly when loading state doesn't matter
    return ProfileDetails(
      data: bloc.state.details,
      // Pass status-dependent properties
      isEditable: status is! WaitingStatus,
    );
  }

  Widget _buildActions(BuildContext context, StreamStatus status) {
    // Use status type checks for enabling/disabling
    return Row(
      children: [
        ElevatedButton(
          onPressed: status is! WaitingStatus 
              ? () => bloc.send(SaveProfileEvent()) 
              : null,
          child: Text('Save'),
        ),
        if (status is WaitingStatus)
          LoadingSpinner(),
      ],
    );
  }
}
```

#### Pattern 2: Status-Specific Overlays

Keep your main UI stable and overlay status indicators:

```dart
class DataGridWidget extends StatelessJuiceWidget<GridBloc> {
  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    return Stack(
      children: [
        // Main content always visible
        _buildMainContent(bloc.state),
        
        // Status overlays
        if (status is WaitingStatus)
          LoadingOverlay(message: 'Loading data...'),
          
        if (status is FailureStatus)
          ErrorOverlay(
            message: 'Failed to load data',
            onRetry: () => bloc.send(RetryLoadEvent()),
          ),
          
        if (status is CancelingStatus)
          CancelOverlay(message: 'Operation cancelled'),
      ],
    );
  }

  Widget _buildMainContent(GridState state) {
    return GridView.builder(
      itemCount: state.items.length,
      itemBuilder: (context, index) => ItemCard(item: state.items[index]),
    );
  }
}
```

#### Pattern 3: Status-Dependent Behavior

Encapsulate status-dependent logic in helper methods:

```dart
class OrderFormWidget extends StatelessJuiceWidget<OrderBloc> {
  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    return Form(
      child: Column(
        children: [
          OrderDetailsForm(
            initialData: bloc.state.details,
            enabled: _isFormEditable(status),
          ),
          
          AddressSection(
            address: bloc.state.address,
            onEdit: _canEditAddress(status) 
                ? () => bloc.send(EditAddressEvent())
                : null,
          ),
          
          PaymentSection(
            paymentMethods: bloc.state.paymentMethods,
            selectedMethod: bloc.state.selectedMethod,
            onSelect: _canChangePayment(status)
                ? (method) => bloc.send(SelectPaymentEvent(method))
                : null,
          ),
          
          SubmitButton(
            onPressed: _canSubmit(status)
                ? () => bloc.send(SubmitOrderEvent())
                : null,
            child: _getSubmitButtonChild(status),
          ),
        ],
      ),
    );
  }

  bool _isFormEditable(StreamStatus status) {
    return status is! WaitingStatus && 
           status is! CancelingStatus &&
           bloc.state.orderStatus != OrderStatus.submitted;
  }

  bool _canEditAddress(StreamStatus status) {
    return _isFormEditable(status) && 
           !bloc.state.isExpressCheckout;
  }

  bool _canChangePayment(StreamStatus status) {
    return _isFormEditable(status) && 
           bloc.state.paymentMethods.isNotEmpty;
  }

  bool _canSubmit(StreamStatus status) {
    return status is! WaitingStatus &&
           status is! CancelingStatus &&
           bloc.state.isValid &&
           bloc.state.orderStatus == OrderStatus.draft;
  }

  Widget _getSubmitButtonChild(StreamStatus status) {
    if (status is WaitingStatus) {
      return LoadingSpinner();
    }
    return Text('Submit Order');
  }
}
```

#### Pattern 4: Composite Status Handling

For widgets that need to coordinate multiple blocs:

```dart
class CheckoutWidget extends StatelessJuiceWidget2<OrderBloc, PaymentBloc> {
  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    // Handle complex loading states
    final isOrderProcessing = bloc1.currentStatus is WaitingStatus;
    final isPaymentProcessing = bloc2.currentStatus is WaitingStatus;
    
    if (isOrderProcessing && isPaymentProcessing) {
      return FullPageLoader(message: 'Processing your order...');
    }

    return Column(
      children: [
        // Order summary always visible
        OrderSummary(order: bloc1.state.order),
        
        // Payment section with its own loading state
        PaymentSection(
          methods: bloc2.state.methods,
          isLoading: isPaymentProcessing,
        ),
        
        // Status-aware actions
        CheckoutActions(
          onSubmit: _canSubmit ? _handleSubmit : null,
          isProcessing: isOrderProcessing,
        ),
      ],
    );
  }

  bool get _canSubmit {
    final orderStatus = bloc1.currentStatus;
    final paymentStatus = bloc2.currentStatus;
    
    return orderStatus is! WaitingStatus &&
           paymentStatus is! WaitingStatus &&
           bloc1.state.isValid &&
           bloc2.state.selectedMethod != null;
  }
}
```

These patterns help manage complex UIs while keeping your code organized and maintainable. Choose the pattern that best fits your widget's complexity and requirements.