# Logging in Juice

Juice provides a flexible, context-aware logging system that helps you track what's happening in your application. This guide covers everything you need to know about logging in Juice.

## Default Logging

Out of the box, Juice uses a default logger that provides reasonable logging capabilities:

```dart
class MyUseCase extends BlocUseCase<MyBloc, MyEvent> {
  @override
  Future<void> execute(MyEvent event) async {
    // Simple message logging
    log('Processing event');  // Outputs: [MyUseCase] Processing event
    
    try {
      // Do some work...
    } catch (e, stack) {
      // Error logging with stack trace
      logError('Failed to process event', e, stack);
      // Outputs: [MyUseCase] Exception: Failed to process event
      // With full error details and stack trace
    }
  }
}
```

Key features of the default logger:
- Automatic prefixing with use case name
- Error stack trace formatting
- Color coding in development
- Timestamp tracking

## Using Context

The logging system supports rich context to help you track detailed information:

```dart
class OrderUseCase extends BlocUseCase<OrderBloc, ProcessOrderEvent> {
  @override
  Future<void> execute(ProcessOrderEvent event) async {
    // Log with context
    log('Processing order', context: {
      'orderId': event.orderId,
      'amount': event.amount,
      'userId': bloc.state.userId
    });
    // Outputs: [OrderUseCase] Processing order | Context: {orderId: 123, amount: 50.0, userId: abc}
    
    try {
      await processOrder(event.orderId);
    } catch (e, stack) {
      // Error logging with context
      logError(
        'Order processing failed', 
        e, 
        stack,
        context: {
          'orderId': event.orderId,
          'state': bloc.state.status,
          'retryCount': retryCount
        }
      );
    }
  }
}
```

Context is particularly useful for:
- Debugging production issues
- Tracking user flows
- Monitoring system health
- Performance analysis

## Custom Logger Implementation

You can implement your own logging system by creating a class that implements the `JuiceLogger` interface:

```dart
class CustomLogger implements JuiceLogger {
  @override
  void log(String message, {
    Level level = Level.info,
    Map<String, dynamic>? context
  }) {
    // Your custom logging implementation
    final timestamp = DateTime.now().toIso8601String();
    final contextStr = context != null ? ' | $context' : '';
    
    print('[$timestamp][$level] $message$contextStr');
  }

  @override
  void logError(
    String message,
    Object error,
    StackTrace stackTrace, {
    Map<String, dynamic>? context
  }) {
    // Your custom error logging implementation
    final timestamp = DateTime.now().toIso8601String();
    final contextStr = context != null ? ' | $context' : '';
    
    print('[$timestamp][ERROR] $message$contextStr');
    print('Error: $error');
    print('Stack trace:\n$stackTrace');
  }
}
```

Common use cases for custom loggers:
- Integration with logging services (LogRocket, Sentry, etc.)
- Structured logging for analytics
- Environment-specific logging behavior
- Custom formatting or filtering

## Configuring Your Logger

To use your custom logger:

```dart
void main() {
  // Configure global logger
  JuiceLoggerConfig.configureLogger(CustomLogger());
  
  // Or configure per-bloc logger
  final bloc = MyBloc(customLogger: CustomLogger());
  
  runApp(MyApp());
}
```

## Best Practices

1. **Use Context Effectively**
```dart
// ❌ Poor context usage
log('Error occurred', context: {'error': 'Failed'});

// ✅ Rich, useful context
log('Payment processing failed', context: {
  'transactionId': tx.id,
  'amount': payment.amount,
  'provider': paymentProvider.name,
  'customerType': customer.type,
  'retryCount': attempts
});
```

2. **Log Appropriate Levels**
```dart
// Log important business events
log('Order placed successfully', level: Level.info);

// Log debugging information
log('Cache miss, fetching from network', level: Level.debug);

// Log warnings
log('Rate limit approaching', level: Level.warning);

// Log errors
logError('Payment processing failed', error, stack);
```

3. **Structure Context Data**
```dart
// ❌ Unstructured context
log('User action', context: {
  'data': 'user 123 clicked button'
});

// ✅ Structured context
log('User action', context: {
  'userId': '123',
  'action': 'button_click',
  'component': 'checkout_form',
  'timestamp': DateTime.now().toIso8601String()
});
```

4. **Include Relevant State**
```dart
class CheckoutUseCase extends BlocUseCase<CheckoutBloc, CheckoutEvent> {
  @override
  Future<void> execute(CheckoutEvent event) async {
    log('Processing checkout', context: {
      'cart': {
        'itemCount': bloc.state.cart.items.length,
        'total': bloc.state.cart.total,
        'currency': bloc.state.currency
      },
      'customer': {
        'id': bloc.state.customerId,
        'type': bloc.state.customerType
      },
      'session': {
        'id': bloc.state.sessionId,
        'duration': bloc.state.sessionDuration
      }
    });
  }
}
```

## Production Considerations

1. **Sensitive Data**
   - Never log passwords, tokens, or sensitive user data
   - Mask or truncate potentially sensitive information
   - Be careful with user identifiable information (PII)

2. **Performance**
   - Consider logging volume in production
   - Use sampling for high-frequency events
   - Implement log rotation or cleanup
   - Be mindful of string concatenation

3. **Error Reporting**
   - Always include stack traces with errors
   - Provide enough context to reproduce issues
   - Consider error grouping/categorization
   - Track error frequencies and patterns

4. **Monitoring**
   - Use structured logging for metrics
   - Track performance indicators
   - Monitor error rates
   - Set up alerts for critical issues

## Example Production Logger

Here's an example of a production-ready logger:

```dart
class ProductionLogger implements JuiceLogger {
  final LoggingService _loggingService;
  final ErrorReporting _errorReporting;
  final bool _isProd;
  
  ProductionLogger({
    required LoggingService loggingService,
    required ErrorReporting errorReporting,
    required bool isProd,
  })  : _loggingService = loggingService,
        _errorReporting = errorReporting,
        _isProd = isProd;

  @override
  void log(String message, {
    Level level = Level.info,
    Map<String, dynamic>? context
  }) async {
    // Clean and validate context
    final safeContext = _sanitizeContext(context);
    
    // Add standard fields
    final enrichedContext = {
      'timestamp': DateTime.now().toIso8601String(),
      'level': level.toString(),
      'environment': _isProd ? 'prod' : 'dev',
      ...safeContext ?? {},
    };
    
    // Send to logging service
    await _loggingService.log(
      message,
      level: level,
      context: enrichedContext
    );
  }

  @override
  void logError(
    String message,
    Object error,
    StackTrace stackTrace, {
    Map<String, dynamic>? context
  }) async {
    // Clean and validate context
    final safeContext = _sanitizeContext(context);
    
    // Report error
    await _errorReporting.captureException(
      error,
      stackTrace: stackTrace,
      context: safeContext
    );
    
    // Log error details
    await log(
      message,
      level: Level.error,
      context: {
        'error': error.toString(),
        'stackTrace': stackTrace.toString(),
        ...safeContext ?? {},
      }
    );
  }
  
  Map<String, dynamic>? _sanitizeContext(Map<String, dynamic>? context) {
    if (context == null) return null;
    
    return context.map((key, value) {
      // Mask sensitive fields
      if (_isSensitive(key)) {
        return MapEntry(key, '***');
      }
      
      // Clean values
      if (value is String) {
        return MapEntry(key, _sanitizeString(value));
      }
      
      return MapEntry(key, value);
    });
  }
  
  bool _isSensitive(String key) {
    return key.toLowerCase().contains(RegExp(
      r'password|token|secret|key|credential|auth'
    ));
  }
  
  String _sanitizeString(String value) {
    // Remove common sensitive patterns
    return value.replaceAll(RegExp(
      r'([0-9]{4})[0-9]*([0-9]{4})'
    ), r'$1****$2');
  }
}
```

## Debugging Tips

1. **Temporary Debug Logging**
```dart
// Add detailed logging for debugging
log('Cache state', context: {
  'entries': cache.length,
  'size': cache.size,
  'hits': cache.hits,
  'misses': cache.misses,
  'oldestEntry': cache.oldest?.timestamp,
  'newestEntry': cache.newest?.timestamp,
});
```

2. **State Transitions**
```dart
@override
void emitUpdate({
  BlocState? newState,
  Set<String>? groupsToRebuild
}) {
  log('State transition', context: {
    'oldState': bloc.state.toString(),
    'newState': newState.toString(),
    'groups': groupsToRebuild?.toList(),
    'timestamp': DateTime.now().toIso8601String()
  });
  
  super.emitUpdate(
    newState: newState,
    groupsToRebuild: groupsToRebuild
  );
}
```

3. **Performance Tracking**
```dart
Future<void> complexOperation() async {
  final stopwatch = Stopwatch()..start();
  
  try {
    await doWork();
  } finally {
    stopwatch.stop();
    log('Operation completed', context: {
      'duration': stopwatch.elapsedMilliseconds,
      'operation': 'complexOperation'
    });
  }
}
```

Remember that logging is a crucial tool for understanding and maintaining your application. Take time to implement good logging practices early in your development process.