# JuiceSelector - Optimized State Selection

`JuiceSelector` is a widget that rebuilds only when a specific portion of state changes. This provides more granular control than rebuild groups and eliminates unnecessary widget rebuilds.

## Overview

Traditional approaches rebuild widgets on any state change:

```dart
// Rebuilds whenever ANY state property changes
class CounterDisplay extends StatelessJuiceWidget<CounterBloc> {
  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    return Text('Count: ${bloc.state.count}');
  }
}
```

With `JuiceSelector`, you specify exactly what to watch:

```dart
// Only rebuilds when count changes
JuiceSelector<CounterBloc, CounterState, int>(
  selector: (state) => state.count,
  builder: (context, count) => Text('Count: $count'),
)
```

## Basic Usage

```dart
JuiceSelector<CounterBloc, CounterState, int>(
  selector: (state) => state.count,
  builder: (context, count) {
    return Text(
      'Count: $count',
      style: Theme.of(context).textTheme.headline4,
    );
  },
)
```

The widget:
1. Extracts `count` from state using the selector
2. Only rebuilds when `count` changes (using `==` equality)
3. Passes the selected value directly to the builder

## Type Parameters

```dart
JuiceSelector<TBloc, TState, TSelected>
```

- `TBloc` - The bloc type (e.g., `CounterBloc`)
- `TState` - The state type (e.g., `CounterState`)
- `TSelected` - The type of the selected value (e.g., `int`, `String`, `User`)

## Selecting Different Types

### Primitive Values

```dart
// Select int
JuiceSelector<CounterBloc, CounterState, int>(
  selector: (state) => state.count,
  builder: (context, count) => Text('$count'),
)

// Select String
JuiceSelector<ProfileBloc, ProfileState, String>(
  selector: (state) => state.user.name,
  builder: (context, name) => Text(name),
)

// Select bool
JuiceSelector<SettingsBloc, SettingsState, bool>(
  selector: (state) => state.isDarkMode,
  builder: (context, isDark) => Icon(
    isDark ? Icons.dark_mode : Icons.light_mode,
  ),
)
```

### Complex Objects

```dart
// Select object
JuiceSelector<ProfileBloc, ProfileState, User?>(
  selector: (state) => state.currentUser,
  builder: (context, user) {
    if (user == null) return Text('Not logged in');
    return UserAvatar(user: user);
  },
)
```

### Computed Values

```dart
// Select computed value
JuiceSelector<TodoBloc, TodoState, int>(
  selector: (state) => state.todos.where((t) => t.isCompleted).length,
  builder: (context, completedCount) => Text('Done: $completedCount'),
)
```

## Custom Equality with JuiceSelectorWith

For complex types where `==` isn't sufficient, use `JuiceSelectorWith`:

```dart
JuiceSelectorWith<TodoBloc, TodoState, List<Todo>>(
  selector: (state) => state.todos,
  equals: (previous, current) => listEquals(previous, current),
  builder: (context, todos) => TodoList(todos: todos),
)
```

This is useful for:
- Lists and collections
- Objects without proper `==` implementation
- Deep equality comparisons

## Providing a Bloc Instance

By default, `JuiceSelector` looks up the bloc from `BlocScope`. You can provide a specific instance:

```dart
JuiceSelector<CounterBloc, CounterState, int>(
  bloc: mySpecificBloc,  // Optional: provide bloc instance
  selector: (state) => state.count,
  builder: (context, count) => Text('$count'),
)
```

## Using the Stream Extension

For non-widget use cases, use the `select` extension on blocs:

```dart
// Create a stream of selected values
final countStream = bloc.select((state) => state.count);

countStream.listen((count) {
  print('Count changed to: $count');
});

// With custom equality
final todosStream = bloc.selectWith(
  (state) => state.todos,
  equals: (a, b) => listEquals(a, b),
);
```

## Practical Examples

### Counter with Multiple Displays

```dart
class CounterPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Only rebuilds when count changes
        JuiceSelector<CounterBloc, CounterState, int>(
          selector: (state) => state.count,
          builder: (context, count) => Text('Count: $count'),
        ),

        // Only rebuilds when message changes
        JuiceSelector<CounterBloc, CounterState, String>(
          selector: (state) => state.message,
          builder: (context, message) => Text(message),
        ),

        // Never rebuilds (static button)
        ElevatedButton(
          onPressed: () => BlocScope.get<CounterBloc>().send(IncrementEvent()),
          child: Text('Increment'),
        ),
      ],
    );
  }
}
```

### User Profile

```dart
class ProfileHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Only rebuilds when avatar URL changes
        JuiceSelector<ProfileBloc, ProfileState, String?>(
          selector: (state) => state.user?.avatarUrl,
          builder: (context, avatarUrl) => CircleAvatar(
            backgroundImage: avatarUrl != null
                ? NetworkImage(avatarUrl)
                : null,
          ),
        ),

        // Only rebuilds when name changes
        JuiceSelector<ProfileBloc, ProfileState, String>(
          selector: (state) => state.user?.name ?? 'Guest',
          builder: (context, name) => Text(name),
        ),
      ],
    );
  }
}
```

### Shopping Cart

```dart
class CartSummary extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Item count badge
        JuiceSelector<CartBloc, CartState, int>(
          selector: (state) => state.items.length,
          builder: (context, count) => Badge(
            label: Text('$count'),
            child: Icon(Icons.shopping_cart),
          ),
        ),

        // Total price
        JuiceSelector<CartBloc, CartState, double>(
          selector: (state) => state.totalPrice,
          builder: (context, total) => Text('\$${total.toStringAsFixed(2)}'),
        ),
      ],
    );
  }
}
```

### Loading State Indicator

```dart
JuiceSelector<DataBloc, DataState, bool>(
  selector: (state) => state.isLoading,
  builder: (context, isLoading) {
    if (isLoading) {
      return CircularProgressIndicator();
    }
    return SizedBox.shrink();
  },
)
```

## Comparison with Alternatives

### vs Rebuild Groups

| Feature | JuiceSelector | Rebuild Groups |
|---------|---------------|----------------|
| Granularity | Per-property | Per-group |
| Setup | Inline | Define groups + emit |
| Equality | Automatic | N/A |
| Use case | Fine-grained | Coarse-grained |

Use `JuiceSelector` when:
- You need per-property rebuild control
- You want automatic equality checking
- You're selecting computed values

Use rebuild groups when:
- Multiple widgets should update together
- You have well-defined UI sections
- You need to coordinate updates

### vs StatelessJuiceWidget with Groups

```dart
// Rebuild groups approach
class CounterDisplay extends StatelessJuiceWidget<CounterBloc> {
  CounterDisplay({super.groups = const {"counter"}});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    return Text('${bloc.state.count}');
  }
}

// JuiceSelector approach
JuiceSelector<CounterBloc, CounterState, int>(
  selector: (state) => state.count,
  builder: (context, count) => Text('$count'),
)
```

## Best Practices

### 1. Keep Selectors Simple

```dart
// Good - simple property access
selector: (state) => state.count

// Good - simple computation
selector: (state) => state.items.length

// Avoid - complex computation in selector
selector: (state) => expensiveComputation(state.data)
```

### 2. Use Memoization for Expensive Computations

If you need expensive computations, do them in the state:

```dart
// In state class
class TodoState extends BlocState {
  final List<Todo> todos;

  // Compute once, cache in state
  late final int completedCount = todos.where((t) => t.completed).length;
}

// In widget - just select the precomputed value
selector: (state) => state.completedCount
```

### 3. Prefer Multiple Selectors Over One Complex One

```dart
// Good - separate selectors
Column(
  children: [
    JuiceSelector<...>(selector: (s) => s.name, ...),
    JuiceSelector<...>(selector: (s) => s.email, ...),
  ],
)

// Avoid - tuple/record selector
JuiceSelector<..., (String, String)>(
  selector: (s) => (s.name, s.email),
  builder: (context, values) => ...,
)
```

### 4. Use JuiceSelectorWith for Collections

```dart
// For lists, use custom equality
JuiceSelectorWith<TodoBloc, TodoState, List<Todo>>(
  selector: (state) => state.todos,
  equals: listEquals,
  builder: ...,
)
```

## API Reference

### JuiceSelector

| Property | Type | Description |
|----------|------|-------------|
| `selector` | `T Function(TState)` | Extracts value from state |
| `builder` | `Widget Function(BuildContext, T)` | Builds widget with selected value |
| `bloc` | `TBloc?` | Optional bloc instance |

### JuiceSelectorWith

| Property | Type | Description |
|----------|------|-------------|
| `selector` | `T Function(TState)` | Extracts value from state |
| `equals` | `bool Function(T, T)` | Custom equality function |
| `builder` | `Widget Function(BuildContext, T)` | Builds widget with selected value |
| `bloc` | `TBloc?` | Optional bloc instance |

### Stream Extensions

```dart
// On JuiceBloc
Stream<T> select<T>(T Function(TState) selector)

Stream<T> selectWith<T>(
  T Function(TState) selector, {
  required bool Function(T, T) equals,
})
```
