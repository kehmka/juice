# State Management in Juice

## BlocState Fundamentals

BlocState is the foundation of state management in Juice. All bloc states must extend BlocState:

```dart
// Basic state implementation
class CounterState extends BlocState {
  final int count;
  
  CounterState({required this.count});
  
  CounterState copyWith({int? count}) {
    return CounterState(count: count ?? this.count);
  }
  
  @override
  bool operator ==(Object other) =>
    identical(this, other) ||
    other is CounterState &&
    runtimeType == other.runtimeType &&
    count == other.count;

  @override
  int get hashCode => count.hashCode;
}
```

### Best Practices for State Design

1. **Make States Immutable**
```dart
class UserState extends BlocState {
  // Use final for all fields
  final User user;
  final List<Order> orders;
  
  // Use const constructor when possible
  const UserState({
    required this.user,
    required this.orders,
  });
  
  // Create an unmodifiable view of collections
  List<Order> get safeOrders => List.unmodifiable(orders);
}
```

2. **Implement CopyWith Methods**
```dart
class UserState extends BlocState {
  final User user;
  final List<Order> orders;
  final bool isVerified;
  
  const UserState({
    required this.user,
    required this.orders,
    this.isVerified = false,
  });
  
  UserState copyWith({
    User? user,
    List<Order>? orders,
    bool? isVerified,
  }) {
    return UserState(
      user: user ?? this.user,
      orders: orders ?? this.orders,
      isVerified: isVerified ?? this.isVerified,
    );
  }
}
```

3. **Implement Equality**
```dart
class UserState extends BlocState {
  final User user;
  final List<Order> orders;
  
  @override
  bool operator ==(Object other) =>
    identical(this, other) ||
    other is UserState &&
    runtimeType == other.runtimeType &&
    user == other.user &&
    listEquals(orders, other.orders);

  @override
  int get hashCode => Object.hash(user, Object.hashAll(orders));
}
```

## State Organization

### Nested States
When dealing with complex state, organize it into logical sub-states:

```dart
// Base state for auth feature
class AuthState extends BlocState {
  final User? user;
  final AuthStatus status;
  final String? error;
  
  const AuthState({
    this.user,
    required this.status,
    this.error,
  });
}

// Specific states for different auth scenarios
class SignInState extends AuthState {
  final String email;
  final bool isEmailValid;
  
  const SignInState({
    required this.email,
    required this.isEmailValid,
    required super.status,
    super.error,
  });
}

class SignUpState extends AuthState {
  final String email;
  final String? verificationCode;
  final bool isCodeSent;
  
  const SignUpState({
    required this.email,
    this.verificationCode,
    required this.isCodeSent,
    required super.status,
    super.error,
  });
}
```

### State Composition
Break large states into manageable pieces:

```dart
// Main state composed of smaller states
class AppState extends BlocState {
  final UserState userState;
  final PreferencesState prefsState;
  final NavigationState navState;
  
  const AppState({
    required this.userState,
    required this.prefsState,
    required this.navState,
  });
  
  static AppState initial() => AppState(
    userState: UserState.initial(),
    prefsState: PreferencesState.initial(),
    navState: NavigationState.initial(),
  );
}

// Helper methods for state updates
class AppState extends BlocState {
  AppState updateUser(User newUser) {
    return copyWith(
      userState: userState.copyWith(user: newUser),
    );
  }
  
  AppState updatePreference(String key, dynamic value) {
    return copyWith(
      prefsState: prefsState.updatePreference(key, value),
    );
  }
}
```

## State Updates

### Through Use Cases
The primary way to update state is through use cases:

```dart
class UpdateUserUseCase extends BlocUseCase<ProfileBloc, UpdateUserEvent> {
  @override
  Future<void> execute(UpdateUserEvent event) async {
    // Show loading state
    emitWaiting(groupsToRebuild: {"profile"});
    
    try {
      final updatedUser = await userService.updateUser(event.userUpdate);
      
      // Update state with new user data
      emitUpdate(
        newState: bloc.state.copyWith(user: updatedUser),
        groupsToRebuild: {"profile", "header"},
      );
    } catch (e) {
      emitFailure(groupsToRebuild: {"profile"});
    }
  }
}
```

### Coordinating Multiple States
When updates affect multiple parts of the app:

```dart
class CompleteOrderUseCase extends BlocUseCase<OrderBloc, CompleteOrderEvent> {
  @override
  Future<void> execute(CompleteOrderEvent event) async {
    emitWaiting();
    
    try {
      // Update order state
      final updatedOrder = await orderService.complete(event.orderId);
      
      // Notify interested blocs through relay
      bloc.send(OrderCompletedEvent(order: updatedOrder));
      
      // Update local state
      emitUpdate(
        newState: bloc.state.copyWith(
          currentOrder: updatedOrder,
          completedOrders: [...bloc.state.completedOrders, updatedOrder],
        ),
        groupsToRebuild: {"orders", "status"},
      );
      
    } catch (e) {
      emitFailure();
    }
  }
}
```

## Advanced State Patterns

### Derived State
Compute derived state through getters:

```dart
class OrderState extends BlocState {
  final List<Order> orders;
  final Map<String, OrderStatus> statusMap;
  
  // Derived states
  List<Order> get pendingOrders => 
    orders.where((o) => o.status == OrderStatus.pending).toList();
    
  double get totalRevenue =>
    orders.fold(0, (sum, order) => sum + order.total);
    
  Map<OrderStatus, int> get ordersByStatus =>
    orders.fold({}, (map, order) {
      map[order.status] = (map[order.status] ?? 0) + 1;
      return map;
    });
}
```

### State History
Track state changes for undo/redo:

```dart
class EditorState extends BlocState {
  final Document currentDocument;
  final List<Document> history;
  final int historyIndex;
  
  bool get canUndo => historyIndex > 0;
  bool get canRedo => historyIndex < history.length - 1;
  
  EditorState undo() {
    if (!canUndo) return this;
    return copyWith(
      currentDocument: history[historyIndex - 1],
      historyIndex: historyIndex - 1,
    );
  }
  
  EditorState redo() {
    if (!canRedo) return this;
    return copyWith(
      currentDocument: history[historyIndex + 1],
      historyIndex: historyIndex + 1,
    );
  }
  
  EditorState addChange(Document newDocument) {
    // Remove any redo history
    final newHistory = history.sublist(0, historyIndex + 1);
    return copyWith(
      currentDocument: newDocument,
      history: [...newHistory, newDocument],
      historyIndex: historyIndex + 1,
    );
  }
}
```

### State Validation
Add validation logic to states:

```dart
class FormState extends BlocState {
  final String email;
  final String password;
  final String? confirmPassword;
  
  bool get isEmailValid => 
    email.isNotEmpty && email.contains('@');
    
  bool get isPasswordValid =>
    password.length >= 8;
    
  bool get doPasswordsMatch =>
    confirmPassword != null && password == confirmPassword;
    
  bool get isFormValid =>
    isEmailValid && isPasswordValid && doPasswordsMatch;
    
  List<String> get validationErrors {
    final errors = <String>[];
    if (!isEmailValid) errors.add('Invalid email');
    if (!isPasswordValid) errors.add('Password too short');
    if (!doPasswordsMatch) errors.add('Passwords do not match');
    return errors;
  }
}
```

## Best Practices Summary

1. **Keep States Immutable**
   - Use final fields
   - Return new instances on updates
   - Use const constructors when possible

2. **Design for Change**
   - Implement thorough copyWith methods
   - Consider future state needs
   - Break complex states into sub-states

3. **Optimize for Performance**
   - Implement proper equality
   - Use derived state for computations
   - Consider memoization for expensive calculations

4. **Think About Maintenance**
   - Document state structure
   - Keep states focused
   - Use clear naming conventions

5. **Handle Edge Cases**
   - Consider null states
   - Add validation
   - Track state transitions

Remember: Good state design is crucial for maintainable applications. Take time to plan your state structure and update patterns.