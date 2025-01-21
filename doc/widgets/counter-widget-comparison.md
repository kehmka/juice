# Counter Widget Implementation Comparison

A direct comparison of counter widget implementations across different frameworks, focusing purely on the widget/UI layer.

## Juice
```dart
// Count display widget
class CounterWidget extends StatelessJuiceWidget<CounterBloc> {
  CounterWidget({super.key, super.groups = const {"counter"}});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    return Text(
      'Count: ${bloc.state.count}',
      style: const TextStyle(fontSize: 32),
    );
  }
}

// Buttons widget
class CounterButtons extends StatelessJuiceWidget<CounterBloc> {
  CounterButtons({super.key, super.groups = optOutOfRebuilds});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ElevatedButton(
          onPressed: () => bloc.send(IncrementEvent()),
          child: const Text('+'),
        ),
        const SizedBox(width: 16),
        ElevatedButton(
          onPressed: () => bloc.send(DecrementEvent()),
          child: const Text('-'),
        ),
      ],
    );
  }
}
```

## Riverpod
```dart
// Combined widget
class CounterWidget extends ConsumerWidget {
  const CounterWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(counterProvider);
    
    return Column(
      children: [
        Text(
          'Count: $count',
          style: const TextStyle(fontSize: 32),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () => ref.read(counterProvider.notifier).increment(),
              child: const Text('+'),
            ),
            const SizedBox(width: 16),
            ElevatedButton(
              onPressed: () => ref.read(counterProvider.notifier).decrement(),
              child: const Text('-'),
            ),
          ],
        ),
      ],
    );
  }
}
```

## Bloc Library
```dart
// Combined widget
class CounterView extends StatelessWidget {
  const CounterView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CounterBloc, int>(
      builder: (context, count) {
        return Column(
          children: [
            Text(
              'Count: $count',
              style: const TextStyle(fontSize: 32),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: () => context
                      .read<CounterBloc>()
                      .add(IncrementPressed()),
                  child: const Text('+'),
                ),
                const SizedBox(width: 16),
                ElevatedButton(
                  onPressed: () => context
                      .read<CounterBloc>()
                      .add(DecrementPressed()),
                  child: const Text('-'),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
```

## Provider
```dart
// Combined widget
class CounterWidget extends StatelessWidget {
  const CounterWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Consumer<Counter>(
          builder: (context, counter, child) => Text(
            'Count: ${counter.count}',
            style: const TextStyle(fontSize: 32),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () => context.read<Counter>().increment(),
              child: const Text('+'),
            ),
            const SizedBox(width: 16),
            ElevatedButton(
              onPressed: () => context.read<Counter>().decrement(),
              child: const Text('-'),
            ),
          ],
        ),
      ],
    );
  }
}
```

## GetX
```dart
// Combined widget
class CounterWidget extends StatelessWidget {
  final CounterController c = Get.find<CounterController>();

  CounterWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Obx(() => Text(
          'Count: ${c.count.value}',
          style: const TextStyle(fontSize: 32),
        )),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () => c.increment(),
              child: const Text('+'),
            ),
            const SizedBox(width: 16),
            ElevatedButton(
              onPressed: () => c.decrement(),
              child: const Text('-'),
            ),
          ],
        ),
      ],
    );
  }
}
```

## Key Differences in Widget Layer

1. **Widget Composition**
   - Juice naturally separates widgets based on update needs
   - Other frameworks typically combine display and controls in one widget

2. **Rebuild Control**
   - Juice: Explicit control through groups
   - Riverpod: Selective watching of provider state
   - Bloc: Can use buildWhen for conditional rebuilds
   - Provider: Manual Consumer placement
   - GetX: Obx wrapper for reactive widgets

3. **State Access**
   - Juice: Direct through bloc.state
   - Riverpod: Through ref.watch/read
   - Bloc: Through BlocBuilder callback
   - Provider: Through Consumer or context.read
   - GetX: Through controller instance

4. **Action Dispatching**
   - Juice: bloc.send(Event())
   - Riverpod: ref.read(provider.notifier).method()
   - Bloc: context.read<Bloc>().add(Event())
   - Provider: context.read<T>().method()
   - GetX: Direct controller method call