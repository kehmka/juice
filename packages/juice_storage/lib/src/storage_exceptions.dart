import 'package:juice/juice.dart';
import 'storage_state.dart';

/// Base exception for storage operations.
class StorageException extends JuiceException {
  /// Type of storage error.
  final StorageErrorType type;

  /// The storage key involved in the error, if applicable.
  final String? storageKey;

  /// Request ID for correlation, if applicable.
  final String? requestId;

  /// Whether this error is retryable.
  final bool _isRetryable;

  const StorageException(
    super.message, {
    required this.type,
    this.storageKey,
    this.requestId,
    super.cause,
    super.stackTrace,
    bool isRetryable = false,
  }) : _isRetryable = isRetryable;

  @override
  bool get isRetryable => _isRetryable;

  @override
  String toString() {
    final buffer = StringBuffer('StorageException: $message');
    buffer.write(' (type: ${type.name}');
    if (storageKey != null) buffer.write(', key: $storageKey');
    if (requestId != null) buffer.write(', requestId: $requestId');
    buffer.write(')');
    if (cause != null) buffer.write('\nCaused by: $cause');
    return buffer.toString();
  }
}

/// Exception thrown when storage is not initialized.
class StorageNotInitializedException extends StorageException {
  StorageNotInitializedException([String? backend])
      : super(
          backend != null
              ? '$backend storage is not initialized'
              : 'Storage is not initialized',
          type: StorageErrorType.notInitialized,
        );
}

/// Exception thrown when a backend is not available.
class BackendNotAvailableException extends StorageException {
  BackendNotAvailableException(String backend)
      : super(
          '$backend storage is not available on this platform',
          type: StorageErrorType.backendNotAvailable,
        );
}

/// Exception thrown when a Hive box is not open.
class BoxNotOpenException extends StorageException {
  BoxNotOpenException(String boxName)
      : super(
          'Hive box "$boxName" is not open',
          type: StorageErrorType.boxNotOpen,
          storageKey: 'hive:$boxName',
        );
}

/// Exception thrown when a key is not found.
class KeyNotFoundException extends StorageException {
  KeyNotFoundException(String key, {String? backend})
      : super(
          'Key "$key" not found${backend != null ? ' in $backend' : ''}',
          type: StorageErrorType.keyNotFound,
          storageKey: key,
        );
}

/// Exception thrown when a type error occurs during read/write.
class StorageTypeException extends StorageException {
  StorageTypeException(super.message, {super.storageKey})
      : super(type: StorageErrorType.typeError);
}

/// Exception thrown when serialization fails.
class SerializationException extends StorageException {
  SerializationException(super.message, {super.cause, super.storageKey})
      : super(type: StorageErrorType.serializationError);
}

/// Exception thrown when encryption/decryption fails.
class EncryptionException extends StorageException {
  EncryptionException(super.message, {super.cause})
      : super(type: StorageErrorType.encryptionError);
}

/// Exception thrown when a platform feature is not supported.
class PlatformNotSupportedException extends StorageException {
  PlatformNotSupportedException(String feature)
      : super(
          '$feature is not supported on this platform',
          type: StorageErrorType.platformNotSupported,
        );
}

/// Exception thrown for SQLite errors.
class SqliteException extends StorageException {
  SqliteException(super.message, {super.cause, super.isRetryable = false})
      : super(type: StorageErrorType.sqliteError);
}

/// Exception thrown when permission is denied.
class StoragePermissionDeniedException extends StorageException {
  StoragePermissionDeniedException(String operation)
      : super(
          'Permission denied for storage operation: $operation',
          type: StorageErrorType.permissionDenied,
        );
}
