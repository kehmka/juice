# Why Juice?

## The Problem

Flutter developers face several common challenges when building applications:

1. **Business Logic Organization**
   - Where should business logic live?
   - How to avoid massive bloc files?
   - How to make logic reusable and testable?

2. **State Management Complexity**
   - Handling loading, error, and success states
   - Managing concurrent operations
   - Controlling UI updates efficiently

3. **Navigation Management**
   - Type-safe route handling
   - Complex navigation flows
   - Deep linking support

4. **Developer Experience**
   - Maintaining clean code as apps grow
   - Ensuring type safety throughout
   - Making code easy to test and debug

## How Juice Solves These

### 1. Clean Logic Organization

Juice introduces use cases as the primary unit of business logic:

```dart
// Each operation gets its own focused use case
class SendMessageUseCase extends BlocUseCase<ChatBloc, SendMessageEvent> {
  @override
  Future<void> execute(SendMessageEvent event) async {
    emitWaiting(groupsToRebuild: {"chat_status"});
    
    try {
      await chatService.send(event.message);
      emitUpdate(
        newState: ChatState.messageSent(),
        groupsToRebuild: {"chat_messages", "chat_status"}
      );
    } catch (e) {
      emitFailure(groupsToRebuild: {"chat_status"});
    }
  }
}
```

Compare this to traditional bloc pattern:

```dart
// Traditional bloc - mixing multiple concerns
class ChatBloc extends Bloc<ChatEvent, ChatState> {
  ChatBloc() : super(ChatInitial()) {
    on<SendMessage>((event, emit) async {
      emit(ChatLoading());
      try {
        await chatService.send(event.message);
        emit(MessageSent());
      } catch (e) {
        emit(ChatError(e.toString()));
      }
    });

    on<LoadMessages>((event, emit) async {
      // More mixed logic...
    });

    on<DeleteMessage>((event, emit) async {
      // Even more mixed logic...
    });
  }
}
```

### 2. Smart State Management

Juice's StreamStatus system provides structured state handling:

```dart
class ChatWidget extends StatelessJuiceWidget<ChatBloc> {
  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    return status.when(
      updating: (_) => MessageList(messages: bloc.state.messages),
      waiting: (_) => LoadingSpinner(),
      error: (_) => ErrorDisplay(),
      canceling: (_) => Text("Operation cancelled"),
    );
  }
}
```

Compare to manual state handling:

```dart
// Manual state handling - more error prone
Widget build(BuildContext context) {
  return BlocBuilder<ChatBloc, ChatState>(
    builder: (context, state) {
      if (state is ChatLoading) {
        return LoadingSpinner();
      } else if (state is ChatError) {
        return ErrorDisplay(state.error);
      } else if (state is ChatSuccess) {
        return MessageList(state.messages);
      }
      return Container(); // Easy to forget cases
    },
  );
}
```

### 3. Group-Based Rebuilds

Juice provides precise control over widget updates:

```dart
// Only rebuild message list on new messages
class MessageList extends StatelessJuiceWidget<ChatBloc> {
  MessageList({super.key, super.groups = const {"chat_messages"}});
  
  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    return ListView(children: bloc.state.messages.map(/*...*/));
  }
}

// Status updates independently
class ChatStatus extends StatelessJuiceWidget<ChatBloc> {
  ChatStatus({super.key, super.groups = const {"chat_status"}});
  
  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    return Text(bloc.state.status);
  }
}
```

Compare to traditional approaches where rebuild control is more difficult:

```dart
// Traditional approach - harder to control updates
BlocBuilder<ChatBloc, ChatState>(
  buildWhen: (previous, current) {
    // Complex conditions to control rebuilds
    return previous.messages != current.messages;
  },
  builder: (context, state) {
    return MessageList(messages: state.messages);
  },
);
```

## Comparison with Alternatives

### bloc library

**Advantages of bloc library:**
- Mature and widely used
- Large ecosystem
- Simple to get started

**Where Juice improves:**
- Clean separation through use cases
- Built-in operation control
- Smart rebuild system
- Type-safe navigation
- Structured state handling

### Provider

**Advantages of Provider:**
- Very lightweight
- Easy to understand
- Great for simple apps

**Where Juice improves:**
- Better scaling to complex apps
- Built-in state management patterns
- Operation handling (loading, errors)
- Clear architecture guidance

### Riverpod

**Advantages of Riverpod:**
- Modern provider approach
- Great dependency handling
- Strong type safety

**Where Juice improves:**
- More structured architecture
- Better operation handling
- Group-based rebuilds
- Navigation integration

### GetX

**Advantages of GetX:**
- All-in-one solution
- Quick to develop with
- Many utilities included

**Where Juice improves:**
- Cleaner architecture
- Better type safety
- More maintainable as apps grow
- Focused feature set

## When to Use Juice

Juice is particularly well-suited for:

1. **Medium to Large Applications**
   - Clean architecture helps manage complexity
   - Use cases keep logic organized
   - Group rebuilds maintain performance

2. **Team Projects**
   - Clear patterns for consistency
   - Type safety prevents errors
   - Easy to test and maintain

3. **Complex User Flows**
   - Operation handling built in
   - Navigation management included
   - State transitions handled cleanly

4. **Long-Term Projects**
   - Architecture scales well
   - Easy to add features
   - Maintainable over time

## When Another Solution Might Be Better

Consider alternatives when:

1. **Building a Very Simple App**
   - Provider might be simpler for basic state
   - bloc library for familiar patterns
   - GetX for rapid development

2. **Need Minimal Dependencies**
   - Provider is more lightweight
   - Manual state management might suffice

3. **Specific Feature Requirements**
   - If you need features specific to other frameworks
   - When integrating with existing solutions

## Conclusion

Juice combines the best aspects of existing solutions while adding unique features that make development more enjoyable and maintainable. It's particularly strong for teams building complex applications that need to remain maintainable over time.

The framework is opinionated where it helps (architecture, patterns) but flexible where you need it (implementation details, integration). This balance helps teams build better applications while staying productive.