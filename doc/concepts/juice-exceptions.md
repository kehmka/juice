# JuiceException - Typed Error Handling

Juice provides a hierarchy of typed exceptions that enable consistent error handling across your application. These exceptions integrate with `FailureStatus` to provide rich error context in your UI.

## Overview

The exception hierarchy allows you to:
- Categorize errors by type (network, validation, timeout, etc.)
- Determine if errors are retryable
- Access error-specific context (status codes, field names, etc.)
- Build consistent error handling patterns

## Exception Hierarchy

```
JuiceException (abstract)
├── NetworkException      - Network/HTTP errors
├── ValidationException   - Input validation failures
├── JuiceTimeoutException - Operation timeouts
├── CancelledException    - Cancelled operations
├── StateException        - Invalid state transitions
└── ConfigurationException - Setup/configuration errors
```

## Base Exception

All Juice exceptions extend `JuiceException`:

```dart
abstract class JuiceException implements Exception {
  final String message;
  final Object? cause;
  final StackTrace? stackTrace;

  bool get isRetryable;
  bool get isNetworkError => false;
  bool get isValidationError => false;
  bool get isTimeoutError => false;
}
```

## Exception Types

### NetworkException

For HTTP failures, connection issues, and network errors:

```dart
// Creating network exceptions
throw NetworkException('Server error', statusCode: 500);
throw NetworkException('No internet connection', cause: socketException);

// Properties
exception.statusCode     // HTTP status code
exception.isClientError  // true for 4xx codes
exception.isServerError  // true for 5xx codes
exception.isRetryable    // true (network errors are retryable)
exception.isNetworkError // true
```

**Example Usage:**

```dart
class FetchDataUseCase extends BlocUseCase<DataBloc, FetchEvent> {
  @override
  Future<void> execute(FetchEvent event) async {
    emitWaiting();

    try {
      final response = await http.get(url);

      if (response.statusCode >= 500) {
        throw NetworkException(
          'Server error',
          statusCode: response.statusCode,
        );
      }

      if (response.statusCode >= 400) {
        throw NetworkException(
          'Request failed',
          statusCode: response.statusCode,
        );
      }

      emitUpdate(newState: DataState.loaded(response.body));

    } on SocketException catch (e) {
      throw NetworkException('No internet connection', cause: e);
    } on NetworkException catch (e) {
      emitFailure(error: e, errorStackTrace: StackTrace.current);
    }
  }
}
```

### ValidationException

For input validation failures:

```dart
// Single field validation
throw ValidationException('Email is required', field: 'email');
throw ValidationException('Must be at least 8 characters', field: 'password');

// Multiple field errors
throw ValidationException(
  'Form has errors',
  errors: {
    'email': 'Invalid email format',
    'password': 'Too short',
  },
);

// Properties
exception.field           // Field that failed validation
exception.errors          // Map of field -> error message
exception.isRetryable     // false (user must fix input)
exception.isValidationError // true
```

**Example Usage:**

```dart
class SubmitFormUseCase extends BlocUseCase<FormBloc, SubmitEvent> {
  @override
  Future<void> execute(SubmitEvent event) async {
    // Validate input
    if (event.email.isEmpty) {
      emitFailure(
        error: ValidationException('Email is required', field: 'email'),
      );
      return;
    }

    if (!emailRegex.hasMatch(event.email)) {
      emitFailure(
        error: ValidationException('Invalid email format', field: 'email'),
      );
      return;
    }

    // Process valid input...
  }
}
```

### JuiceTimeoutException

For operation timeouts:

```dart
throw JuiceTimeoutException(
  'Operation timed out',
  duration: Duration(seconds: 30),
);

// Properties
exception.duration      // Timeout duration
exception.isRetryable   // true
exception.isTimeoutError // true
```

**Example Usage:**

```dart
class LongOperationUseCase extends BlocUseCase<Bloc, LongEvent> {
  @override
  Future<void> execute(LongEvent event) async {
    emitWaiting();

    try {
      await longOperation().timeout(Duration(seconds: 30));
      emitUpdate(newState: SuccessState());

    } on TimeoutException catch (e) {
      emitFailure(
        error: JuiceTimeoutException(
          'Operation took too long',
          duration: Duration(seconds: 30),
          cause: e,
        ),
      );
    }
  }
}
```

### CancelledException

For user-cancelled operations:

```dart
throw CancelledException('Upload cancelled by user');

// Properties
exception.isRetryable // false
```

**Example Usage:**

```dart
class UploadUseCase extends BlocUseCase<Bloc, UploadEvent> {
  @override
  Future<void> execute(UploadEvent event) async {
    if (event is CancellableEvent && event.isCancelled) {
      emitFailure(error: CancelledException('Upload cancelled'));
      return;
    }
    // Continue with upload...
  }
}
```

### StateException

For invalid state transitions:

```dart
throw StateException('Cannot send events to a closed bloc');
throw StateException('Invalid state transition from Loading to Error');
```

### ConfigurationException

For setup and configuration errors:

```dart
throw ConfigurationException('MyBloc is not registered');
throw ConfigurationException('Missing required dependency: ApiClient');
```

## Integration with FailureStatus

Exceptions integrate with `FailureStatus` to provide error context:

```dart
// In use case
emitFailure(
  newState: state.copyWith(hasError: true),
  error: NetworkException('Server error', statusCode: 500),
  errorStackTrace: StackTrace.current,
);

// In widget
JuiceBuilder<DataBloc>(
  builder: (context, bloc, status) {
    if (status is FailureStatus) {
      final error = status.error;

      if (error is NetworkException) {
        return ErrorView(
          message: error.message,
          canRetry: error.isRetryable,
          details: 'Status: ${error.statusCode}',
        );
      }

      if (error is ValidationException) {
        return FormError(
          field: error.field,
          message: error.message,
        );
      }
    }

    return DataView(data: bloc.state.data);
  },
)
```

## Creating Custom Exceptions

Extend `JuiceException` for domain-specific errors:

```dart
class PaymentException extends JuiceException {
  const PaymentException(
    super.message, {
    this.errorCode,
    super.cause,
    super.stackTrace,
  });

  final String? errorCode;

  @override
  bool get isRetryable => errorCode != 'CARD_DECLINED';

  bool get isCardDeclined => errorCode == 'CARD_DECLINED';
  bool get isInsufficientFunds => errorCode == 'INSUFFICIENT_FUNDS';

  @override
  String toString() {
    if (errorCode != null) {
      return 'PaymentException: $message (code: $errorCode)';
    }
    return 'PaymentException: $message';
  }
}

// Usage
throw PaymentException(
  'Payment failed',
  errorCode: 'CARD_DECLINED',
);
```

## Error Handling Patterns

### Centralized Error Handling

```dart
class BaseUseCase<B extends JuiceBloc, E extends EventBase>
    extends BlocUseCase<B, E> {

  Future<void> safeExecute(Future<void> Function() operation) async {
    try {
      await operation();
    } on NetworkException catch (e, stack) {
      logError(e, stack);
      emitFailure(error: e, errorStackTrace: stack);
    } on ValidationException catch (e, stack) {
      emitFailure(error: e, errorStackTrace: stack);
    } on JuiceException catch (e, stack) {
      logError(e, stack);
      emitFailure(error: e, errorStackTrace: stack);
    } catch (e, stack) {
      logError(e, stack);
      emitFailure(
        error: StateException('Unexpected error: $e', cause: e),
        errorStackTrace: stack,
      );
    }
  }
}
```

### Retry Logic Based on Exception Type

```dart
Widget buildErrorView(FailureStatus status) {
  final error = status.error;

  if (error is JuiceException && error.isRetryable) {
    return RetryableErrorView(
      message: error.message,
      onRetry: () => bloc.send(RetryEvent()),
    );
  }

  if (error is ValidationException) {
    return ValidationErrorView(
      field: error.field,
      message: error.message,
    );
  }

  return GenericErrorView(message: error?.toString() ?? 'Unknown error');
}
```

## Best Practices

1. **Use specific exception types** - Choose the most specific exception type for your error

2. **Include relevant context** - Add status codes, field names, durations, etc.

3. **Set isRetryable appropriately** - Help the UI decide whether to show retry options

4. **Preserve the cause** - Include the underlying exception for debugging

5. **Include stack traces** - Pass stack traces to `emitFailure` for debugging

6. **Log errors appropriately** - Use the built-in logging before emitting failures

```dart
try {
  // operation
} on NetworkException catch (e, stack) {
  logError(e, stack, context: {'url': url, 'method': 'GET'});
  emitFailure(error: e, errorStackTrace: stack);
}
```
