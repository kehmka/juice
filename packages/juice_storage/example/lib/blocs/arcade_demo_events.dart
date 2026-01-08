import 'package:juice/juice.dart';

import '../demo_entry.dart';

/// Base class for arcade demo events.
sealed class ArcadeDemoEvent extends EventBase {}

/// Event to update the key text field.
class UpdateKeyEvent extends ArcadeDemoEvent {
  UpdateKeyEvent(this.key);
  final String key;
}

/// Event to update the value text field.
class UpdateValueEvent extends ArcadeDemoEvent {
  UpdateValueEvent(this.value);
  final String value;
}

/// Event to select a storage backend.
class SelectBackendEvent extends ArcadeDemoEvent {
  SelectBackendEvent(this.backend);
  final DemoBackend backend;
}

/// Event to update TTL slider value.
class UpdateTtlEvent extends ArcadeDemoEvent {
  UpdateTtlEvent(this.seconds);
  final double seconds;
}

/// Event to save an entry to storage.
class SaveEntryEvent extends ArcadeDemoEvent {}

/// Event to read an entry from storage.
class ReadEntryEvent extends ArcadeDemoEvent {
  ReadEntryEvent(this.entryId);
  final String entryId;
}

/// Event to delete an entry from storage.
class DeleteEntryEvent extends ArcadeDemoEvent {
  DeleteEntryEvent(this.entryId);
  final String entryId;
}

/// Event to spawn multiple time-bomb entries.
class SpawnBombsEvent extends ArcadeDemoEvent {}

/// Event to run cache cleanup.
class CleanupCacheEvent extends ArcadeDemoEvent {}

/// Internal event for timer tick (updates currentTime).
class TickEvent extends ArcadeDemoEvent {}
