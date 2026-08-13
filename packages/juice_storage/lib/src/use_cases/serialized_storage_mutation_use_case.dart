import 'package:juice/juice.dart';

import '../storage_bloc.dart';

/// Base class for storage mutations that share the bloc-wide mutation FIFO.
///
/// Storage backends and the TTL index are shared across event types. Serializing
/// only same-type events would still allow, for example, a write and delete for
/// the same key to overtake one another. Read-only queries do not use this base
/// class and remain genuinely concurrent.
abstract class SerializedStorageMutationUseCase<TEvent extends EventBase>
    extends BlocUseCase<StorageBloc, TEvent> {
  @override
  Future<void> execute(TEvent event) {
    return bloc.runStorageMutation(() => executeMutation(event));
  }

  /// Execute this mutation after all earlier storage mutations have completed.
  Future<void> executeMutation(TEvent event);
}
