# JuiceWidgetState

## Overview

`JuiceWidgetState` is Juice's solution for widgets that need to maintain local UI state while still connecting to Juice's reactive state management system. It combines Flutter's `StatefulWidget` capabilities with Juice's bloc integration.

## Comparison with StatelessJuiceWidget

Both widgets provide:
- Reactive updates to bloc state changes
- Smart rebuilding through groups
- Type-safe state access
- Built-in error handling

Key differences:
- `JuiceWidgetState` can maintain local widget state
- Additional lifecycle methods (initState, dispose)
- `prepareForUpdate` method for state changes
- More control over setState timing

## When to Use JuiceWidgetState

Use JuiceWidgetState when your widget needs to:

1. Maintain Local State
```dart
class AnimatedCounter extends StatefulWidget {
  @override
  State<AnimatedCounter> createState() => AnimatedCounterState();
}

class AnimatedCounterState extends JuiceWidgetState<CounterBloc, AnimatedCounter> {
  // Local animation controller
  late AnimationController _controller;
  
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,  // Can use vsync because we're a State
      duration: Duration(milliseconds: 300),
    );
  }
  
  @override
  void prepareForUpdate(StreamStatus status) {
    // Animate on counter changes
    if (status is UpdatingStatus) {
      _controller.forward(from: 0);
    }
  }
  
  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.scale(
          scale: 1.0 + (_controller.value * 0.2),
          child: Text('Count: ${bloc.state.count}'),
        );
      },
    );
  }
  
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
```

2. Handle Complex Input
```dart
class SearchField extends StatefulWidget {
  @override
  State<SearchField> createState() => SearchFieldState();
}

class SearchFieldState extends JuiceWidgetState<SearchBloc, SearchField> {
  late TextEditingController _textController;
  Timer? _debounceTimer;
  
  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: bloc.state.query);
  }
  
  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(Duration(milliseconds: 300), () {
      bloc.send(SearchEvent(query: query));
    });
  }
  
  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    return TextField(
      controller: _textController,
      onChanged: _onSearchChanged,
      decoration: InputDecoration(
        suffixIcon: status is WaitingStatus
          ? CircularProgressIndicator()
          : Icon(Icons.search),
      ),
    );
  }
  
  @override
  void dispose() {
    _textController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }
}
```

3. Coordinate Multiple Animations/Controllers
```dart
class ComplexAnimation extends StatefulWidget {
  @override
  State<ComplexAnimation> createState() => ComplexAnimationState();
}

class ComplexAnimationState extends JuiceWidgetState<AnimationBloc, ComplexAnimation> 
    with TickerProviderStateMixin {
  late AnimationController _slideController;
  late AnimationController _fadeController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;
  
  @override
  void initState() {
    super.initState();
    _initializeAnimations();
  }
  
  void _initializeAnimations() {
    _slideController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 500),
    );
    
    _fadeController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 300),
    );
    
    _slideAnimation = Tween<Offset>(
      begin: Offset(-1.0, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOut,
    ));
    
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(_fadeController);
  }
  
  @override
  void prepareForUpdate(StreamStatus status) {
    if (status is UpdatingStatus) {
      // Coordinate animations based on state changes
      _slideController.forward(from: 0);
      Future.delayed(
        Duration(milliseconds: 200),
        () => _fadeController.forward(from: 0),
      );
    }
  }
  
  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: ContentView(data: bloc.state.data),
      ),
    );
  }
  
  @override
  void dispose() {
    _slideController.dispose();
    _fadeController.dispose();
    super.dispose();
  }
}
```

## Key Methods

### initState()
Called when the widget is first created. Use for initialization.

```dart
@override
void initState() {
  super.initState();
  // Initialize controllers, subscriptions, etc.
  _scrollController = ScrollController();
  _scrollController.addListener(_onScroll);
}
```

### prepareForUpdate(StreamStatus status)
Called before setState when a state change is accepted. Perfect for preparing animations or updating local state.

```dart
@override
void prepareForUpdate(StreamStatus status) {
  if (status is UpdatingStatus &&
      status.state.selectedIndex != status.oldState.selectedIndex) {
    // Prepare scroll position for new selection
    _scrollController.animateTo(
      status.state.selectedIndex * itemHeight,
      duration: Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }
}
```

### onStateChange(StreamStatus status)
First level of control for rebuilds. Return false to prevent rebuild.

```dart
@override
bool onStateChange(StreamStatus status) {
  // Only rebuild if visible items changed
  if (status is UpdatingStatus) {
    final visibleRange = _getVisibleRange();
    return status.state.hasChangesInRange(visibleRange);
  }
  return true;
}
```

### onBuild(BuildContext context, StreamStatus status)
Main build method, called when widget needs to rebuild.

```dart
@override
Widget onBuild(BuildContext context, StreamStatus status) {
  return ListView.builder(
    controller: _scrollController,
    itemCount: bloc.state.items.length,
    itemBuilder: (context, index) {
      final item = bloc.state.items[index];
      return ItemTile(
        item: item,
        isSelected: index == _selectedIndex,
        onTap: () => setState(() => _selectedIndex = index),
      );
    },
  );
}
```

### dispose()
Clean up resources when widget is removed.

```dart
@override
void dispose() {
  _scrollController.dispose();
  _subscription?.cancel();
  super.dispose();
}
```

## Best Practices

1. **Proper Resource Management**
```dart
class ResourcefulWidget extends StatefulWidget {
  @override
  State<ResourcefulWidget> createState() => ResourcefulWidgetState();
}

class ResourcefulWidgetState extends JuiceWidgetState<DataBloc, ResourcefulWidget> {
  StreamSubscription? _subscription;
  final _controllers = <AnimationController>[];
  
  @override
  void dispose() {
    // Clean up all resources
    _subscription?.cancel();
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }
}
```

2. **Smart State Updates**
```dart
class OptimizedWidget extends StatefulWidget {
  @override
  State<OptimizedWidget> createState() => OptimizedWidgetState();
}

class OptimizedWidgetState extends JuiceWidgetState<DataBloc, OptimizedWidget> {
  int _localValue = 0;
  
  @override
  bool onStateChange(StreamStatus status) {
    // Skip rebuilds if local state is more important
    if (_localValue > 0 && status is UpdatingStatus) {
      return false;
    }
    return true;
  }
  
  @override
  void prepareForUpdate(StreamStatus status) {
    // Reset local state when global state changes
    if (status is UpdatingStatus) {
      setState(() => _localValue = 0);
    }
  }
}
```

3. **Separation of Concerns**
```dart
class WellOrganizedWidget extends StatefulWidget {
  @override
  State<WellOrganizedWidget> createState() => WellOrganizedWidgetState();
}

class WellOrganizedWidgetState extends JuiceWidgetState<DataBloc, WellOrganizedWidget> {
  // Group related state
  final _animations = _AnimationGroup();
  final _input = _InputHandlers();
  
  @override
  void initState() {
    super.initState();
    _animations.initialize(this);
    _input.initialize();
  }
  
  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    return Column(
      children: [
        _buildAnimatedContent(),
        _buildInputSection(),
      ],
    );
  }
  
  Widget _buildAnimatedContent() {
    return _animations.build(bloc.state.data);
  }
  
  Widget _buildInputSection() {
    return _input.build(
      onChanged: (value) => bloc.send(UpdateEvent(value))
    );
  }
  
  @override
  void dispose() {
    _animations.dispose();
    _input.dispose();
    super.dispose();
  }
}
```

## Common Patterns

### Form Handling
```dart
class FormWidget extends StatefulWidget {
  @override
  State<FormWidget> createState() => FormWidgetState();
}

class FormWidgetState extends JuiceWidgetState<FormBloc, FormWidget> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _emailController;
  
  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: bloc.state.name);
    _emailController = TextEditingController(text: bloc.state.email);
  }
  
  @override
  void prepareForUpdate(StreamStatus status) {
    if (status is UpdatingStatus) {
      // Update controllers if server data changes
      _nameController.text = status.state.name;
      _emailController.text = status.state.email;
    }
  }
  
  void _onSubmit() {
    if (_formKey.currentState!.validate()) {
      bloc.send(SubmitFormEvent(
        name: _nameController.text,
        email: _emailController.text,
      ));
    }
  }
  
  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          TextFormField(
            controller: _nameController,
            decoration: InputDecoration(labelText: 'Name'),
            validator: (value) =>
              value?.isEmpty ?? true ? 'Required' : null,
          ),
          TextFormField(
            controller: _emailController,
            decoration: InputDecoration(labelText: 'Email'),
            validator: _validateEmail,
          ),
          ElevatedButton(
            onPressed: status is! WaitingStatus ? _onSubmit : null,
            child: status is WaitingStatus
              ? CircularProgressIndicator()
              : Text('Submit'),
          ),
        ],
      ),
    );
  }
  
  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }
}
```

### Complex Animations
```dart
class AnimatedList extends StatefulWidget {
  @override
  State<AnimatedList> createState() => AnimatedListState();
}

class AnimatedListState extends JuiceWidgetState<ListBloc, AnimatedList>
    with TickerProviderStateMixin {
  final _listKey = GlobalKey<AnimatedListState>();
  late List<AnimationController> _itemControllers;
  
  @override
  void initState() {
    super.initState();
    _initializeAnimations();
  }
  
  void _initializeAnimations() {
    _itemControllers = List.generate(
      bloc.state.items.length,
      (index) => AnimationController(
        vsync: this,
        duration: Duration(milliseconds: 300),
      )..forward(),
    );
  }
  
  @override
  void prepareForUpdate(StreamStatus status) {
    if (status is UpdatingStatus) {
      final oldItems = status.oldState.items;
      final newItems = status.state.items;
      
      // Handle item additions/removals with animations
      _updateAnimations(oldItems, newItems);
    }
  }
  
  void _updateAnimations(List<Item> oldItems, List<Item> newItems) {
    // Add animations for new items
    final newCount = newItems.length - oldItems.length;
    if (newCount > 0) {
      for (var i = 0; i < newCount; i++) {
        final controller = AnimationController(
          vsync: this,
          duration: Duration(milliseconds: 300),
        );
        _itemControllers.add(controller);
        controller.forward();
      }
    }
    
    // Remove animations for deleted items
    if (newCount < 0) {
      for (var i = 0; i < -newCount; i++) {
        final controller = _itemControllers.removeLast();
        controller.dispose();
      }
    }
  }
  
  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    return AnimatedList(
      key: _listKey,
      itemBuilder: (context, index, animation) {
        return FadeTransition(
          opacity: _itemControllers[index],
          child: SlideTransition(
            position: animation.drive(Tween(
              begin: Offset(1, 0),
              end: Offset.zero,
            )),
            child: ItemTile(item: bloc.state.items[index]),
          ),
        );
      },
    );
  }
  
  @override
  void dispose() {
    for (final controller in _itemControllers) {
      controller.dispose();
    }
    super.dispose();
  }
}
```

## Summary

JuiceWidgetState provides:
- All the reactive benefits of StatelessJuiceWidget
- Full stateful widget capabilities
- Fine-grained control over state updates
- Rich lifecycle management
- Advanced animation control

### When to Choose JuiceWidgetState

Use JuiceWidgetState when you need:
1. Local UI state management (form inputs, scroll positions, etc.)
2. Animation controllers or other resources requiring disposal
3. Complex state update coordination
4. Access to StatefulWidget lifecycle methods

Use StatelessJuiceWidget when:
1. Widget only displays bloc state
2. No local state is needed
3. Simple UI updates suffice
4. No resource management is required

### Key Takeaways

1. **State Management**
   - Use local state (_variables) for UI-specific data
   - Access bloc state through bloc.state
   - Coordinate local and bloc state in prepareForUpdate

2. **Lifecycle Control**
   - Initialize resources in initState
   - Clean up in dispose
   - Use prepareForUpdate for state transition logic
   - Handle rebuilds efficiently with onStateChange

3. **Resource Management**
   - Always dispose controllers and subscriptions
   - Keep track of resources in instance variables
   - Clean up resources before creating new ones
   - Use proper mixin support (e.g., TickerProviderStateMixin)

4. **Performance Optimization**
   - Use rebuild groups effectively
   - Implement onStateChange for rebuild control
   - Batch setState calls when possible
   - Clean up unused resources promptly

### Example Decision Flow

```dart
// Decision flow for choosing between StatelessJuiceWidget and JuiceWidgetState
if (needsLocalState() ||
    needsResourceManagement() ||
    needsAnimationControllers() ||
    needsLifecycleMethods()) {
  // Use JuiceWidgetState
  class MyWidget extends StatefulWidget {
    @override
    State<MyWidget> createState() => MyWidgetState();
  }
  
  class MyWidgetState extends JuiceWidgetState<MyBloc, MyWidget> {
    // Local state, controllers, etc.
  }
} else {
  // Use StatelessJuiceWidget
  class MyWidget extends StatelessJuiceWidget<MyBloc> {
    // Just the build method
  }
}
```

### A Note About setState

Unlike regular StatefulWidget development where you frequently call setState(), JuiceWidgetState handles most state updates automatically. The framework:

1. Automatically calls setState when bloc state changes (filtered through your groups and onStateChange)
2. Manages the rebuild cycle through StreamStatus
3. Coordinates updates through prepareForUpdate

You rarely need to call setState manually. Only use setState when:
1. Updating purely local UI state that isn't connected to bloc state
2. Managing temporary visual states (like hover effects)

```dart
// ❌ Don't do this - Juice handles bloc state updates
@override
void prepareForUpdate(StreamStatus status) {
  setState(() {  // Unnecessary - Juice will rebuild automatically
    // Handle bloc state update
  });
}

// ✅ Do this - Let Juice handle the update
@override
void prepareForUpdate(StreamStatus status) {
  // Prepare for update, no setState needed
  _animationController.forward();
}

// ✅ Do this - setState for local UI state only
void _onHover(bool isHovered) {
  setState(() => _isHovered = isHovered);  // Local UI state
}
```

Remember: Juice's state management system is designed to minimize manual setState calls and handle most rebuild scenarios automatically. Focus on using the provided lifecycle methods (onStateChange, prepareForUpdate) to coordinate updates rather than managing them manually.