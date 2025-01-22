# State Design in Juice

Juice provides a clear separation of concerns for different types of state in your application. Understanding where different types of state belong helps create maintainable and scalable applications.

## Business Logic State (Bloc State)

Business logic state represents your application's core data model. This state belongs in individual bloc states.

### Example: User Profile Feature

```dart
// Business logic state for user profile
class UserProfileState extends BlocState {
  final User user;
  final List<Post> recentPosts;
  final List<Achievement> achievements;
  final ProfileSettings settings;

  UserProfileState({
    required this.user,
    required this.recentPosts,
    required this.achievements,
    required this.settings,
  });

  // Always implement copyWith for immutable updates
  UserProfileState copyWith({
    User? user,
    List<Post>? recentPosts,
    List<Achievement>? achievements,
    ProfileSettings? settings,
  }) {
    return UserProfileState(
      user: user ?? this.user,
      recentPosts: recentPosts ?? this.recentPosts,
      achievements: achievements ?? this.achievements,
      settings: settings ?? this.settings,
    );
  }
}
```

### Guidelines for Bloc State:
- Keep it immutable
- Include only business data
- Use classes for complex state
- Implement copyWith
- Group related data
- Keep data normalized

## UI State (JuiceWidgetState)

UI state is specific to widget behavior and appearance. This belongs in JuiceWidgetState classes.

```dart
class ProfilePageState extends JuiceWidgetState<UserProfileBloc, ProfilePage> {
  // UI-specific state
  bool _isEditMode = false;
  bool _isExpanded = false;
  double _scrollPosition = 0;

  @override 
  bool onStateChange(StreamStatus status) {
    // Control when to rebuild based on status
    return true;
  }

  @override
  void prepareForUpdate(StreamStatus status) {
    // Update UI state before rebuild if needed
    if (status is UpdatingStatus && status.state.isReadOnly) {
      _isEditMode = false;
    }
  }

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    return Column(
      children: [
        // Access business state through bloc
        UserHeader(user: bloc.state.user),
        
        // Use local UI state for widget behavior
        if (_isExpanded)
          UserDetails(
            achievements: bloc.state.achievements,
            onEdit: () {
              _isEditMode = true;
              bloc.send(StartEditingEvent());
            },
          ),
          
        // Handle loading/error states through StreamStatus
        if (status is WaitingStatus)
          LoadingSpinner(),
      ],
    );
  }
}
```

### Guidelines for UI State in JuiceWidgetState:
- Keep UI logic separate from business logic
- Use onStateChange() to control when rebuilds occur
- Use prepareForUpdate() to modify UI state before rebuilds
- Handle layout state (expanded/collapsed) in widget state
- Track scroll positions or view configurations
- Manage focus and edit modes
- Coordinate UI state with bloc state through events

## Application State (App-Level Bloc)

Application state represents global state that affects multiple features. This belongs in an app-level bloc.

```dart
// App-level state
class AppState extends BlocState {
  final User? currentUser;
  final ThemeMode themeMode;
  final Locale locale;
  final bool isDemoMode;
  final Map<String, FeatureFlag> featureFlags;
  final ConnectionStatus connectionStatus;

  AppState({
    this.currentUser,
    required this.themeMode,
    required this.locale,
    required this.isDemoMode,
    required this.featureFlags,
    required this.connectionStatus,
  });
}

// App-level bloc
class AppBloc extends JuiceBloc<AppState> {
  AppBloc() : super(
    AppState(
      themeMode: ThemeMode.system,
      locale: Locale('en'),
      isDemoMode: false,
      featureFlags: {},
      connectionStatus: ConnectionStatus.online,
    ),
    [
      () => UseCaseBuilder(
        typeOfEvent: UpdateThemeEvent,
        useCaseGenerator: () => UpdateThemeUseCase(),
      ),
      // Other app-level use cases...
    ],
    [], // Aviators
  );
}

// Access app state in widgets
class FeatureWidget extends StatelessJuiceWidget2<FeatureBloc, AppBloc> {
  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    // Access feature state
    final featureData = bloc1.state.data;
    
    // Access app state
    final isEnabled = bloc2.state.featureFlags['myFeature']?.enabled ?? false;
    
    return isEnabled ? FeatureContent(data: featureData) : DisabledView();
  }
}
```

### Guidelines for App State:
- Keep it focused on truly global concerns
- Include authentication state
- Manage theme/localization
- Track feature flags
- Monitor connectivity
- Handle app lifecycle

## State Organization Best Practices

1. **State Location Decision Tree**
   - Is it business data? → Bloc State
   - Is it UI behavior? → Widget State
   - Is it app-wide? → App State

2. **State Dependencies**
```
App State (Global)
   ↓
Bloc States (Features)
   ↓
Widget States (UI)
```

3. **Common Patterns**

```dart
// Feature bloc state - focused on business data
class OrderState extends BlocState {
  final Order order;
  final List<LineItem> items;
  final PaymentStatus paymentStatus;
  
  // Business logic state only
}

// UI state in widget - handles presentation
class OrderPageState extends JuiceWidgetState<OrderBloc, OrderPage> {
  bool _isEditingQuantity = false;
  int _selectedItemIndex = -1;
  
  // UI behavior state only
}

// App state - global concerns
class AppState extends BlocState {
  final AuthStatus authStatus;
  final Map<String, bool> permissions;
  
  // App-wide state only
}
```

4. **State Updates Flow**
```dart
// Top-down state updates
class CheckoutUseCase extends BlocUseCase<OrderBloc, StartCheckoutEvent> {
  @override
  Future<void> execute(StartCheckoutEvent event) async {
    // Check app state first
    final appBloc = resolver.resolve<AppBloc>();
    if (!appBloc.state.isAuthenticated) {
      emitFailure(
        aviatorName: 'login',
        aviatorArgs: {'returnTo': 'checkout'}
      );
      return;
    }

    // Update business state
    emitUpdate(
      newState: OrderState.processing(),
      groupsToRebuild: {'order_status'}
    );
  }
}
```

5. **Testing Recommendations**
- Test bloc states independently
- Mock app state for feature tests
- Test UI state in widget tests
- Verify state transitions
- Check state consistency

Remember: Clear state separation makes your app easier to maintain, test, and debug. Use these patterns consistently across your application for the best results.