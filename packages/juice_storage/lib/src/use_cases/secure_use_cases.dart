import 'package:juice/juice.dart';

import '../adapters/adapters.dart';
import '../storage_bloc.dart';
import '../storage_events.dart';
import '../storage_exceptions.dart';
import '../storage_state.dart';

/// Use case for reading from secure storage.
///
/// Note: Secure storage does NOT support TTL. Secrets require explicit deletion.
class SecureReadUseCase extends BlocUseCase<StorageBloc, SecureReadEvent> {
  @override
  Future<void> execute(SecureReadEvent event) async {
    try {
      final adapter = SecureAdapterFactory.instance;
      if (adapter == null) {
        throw StorageException(
          'Secure storage not initialized',
          type: StorageErrorType.notInitialized,
        );
      }

      final value = await adapter.read(event.key);
      event.succeed(value);
    } catch (e, st) {
      emitFailure(error: e, errorStackTrace: st);
      if (e is StorageException) {
        event.fail(e, st);
      } else {
        event.fail(
          StorageException(
            'Failed to read from secure storage: ${event.key}',
            type: StorageErrorType.encryptionError,
            cause: e,
          ),
          st,
        );
      }
    }
  }
}

/// Use case for writing to secure storage.
class SecureWriteUseCase extends BlocUseCase<StorageBloc, SecureWriteEvent> {
  @override
  Future<void> execute(SecureWriteEvent event) async {
    try {
      final adapter = SecureAdapterFactory.instance;
      if (adapter == null) {
        throw StorageException(
          'Secure storage not initialized',
          type: StorageErrorType.notInitialized,
        );
      }

      await adapter.write(event.key, event.value);

      emitUpdate(
        groupsToRebuild: {StorageBloc.groupSecure},
      );

      event.succeed(null);
    } catch (e, st) {
      emitFailure(error: e, errorStackTrace: st);
      if (e is StorageException) {
        event.fail(e, st);
      } else {
        event.fail(
          StorageException(
            'Failed to write to secure storage: ${event.key}',
            type: StorageErrorType.encryptionError,
            cause: e,
          ),
          st,
        );
      }
    }
  }
}

/// Use case for deleting from secure storage.
class SecureDeleteUseCase extends BlocUseCase<StorageBloc, SecureDeleteEvent> {
  @override
  Future<void> execute(SecureDeleteEvent event) async {
    try {
      final adapter = SecureAdapterFactory.instance;
      if (adapter == null) {
        throw StorageException(
          'Secure storage not initialized',
          type: StorageErrorType.notInitialized,
        );
      }

      await adapter.delete(event.key);

      emitUpdate(
        groupsToRebuild: {StorageBloc.groupSecure},
      );

      event.succeed(null);
    } catch (e, st) {
      emitFailure(error: e, errorStackTrace: st);
      if (e is StorageException) {
        event.fail(e, st);
      } else {
        event.fail(
          StorageException(
            'Failed to delete from secure storage: ${event.key}',
            type: StorageErrorType.encryptionError,
            cause: e,
          ),
          st,
        );
      }
    }
  }
}

/// Use case for deleting all secure storage.
class SecureDeleteAllUseCase extends BlocUseCase<StorageBloc, SecureDeleteAllEvent> {
  @override
  Future<void> execute(SecureDeleteAllEvent event) async {
    try {
      final adapter = SecureAdapterFactory.instance;
      if (adapter == null) {
        throw StorageException(
          'Secure storage not initialized',
          type: StorageErrorType.notInitialized,
        );
      }

      await adapter.clear();

      emitUpdate(
        groupsToRebuild: {StorageBloc.groupSecure},
      );

      event.succeed(null);
    } catch (e, st) {
      emitFailure(error: e, errorStackTrace: st);
      if (e is StorageException) {
        event.fail(e, st);
      } else {
        event.fail(
          StorageException(
            'Failed to clear secure storage',
            type: StorageErrorType.encryptionError,
            cause: e,
          ),
          st,
        );
      }
    }
  }
}
