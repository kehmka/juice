// Juice feature: [RebuildGroup] — type-safe rebuild group constants.
//
// Replaces magic strings like 'notes:list' with compile-time safe
// identifiers. Provides IDE autocomplete, typo prevention, and
// refactoring support. Convert to string sets via .toStringSet().
import 'package:juice/juice.dart';

abstract class NotesGroups {
  static const list = RebuildGroup('notes:list');
  static const search = RebuildGroup('notes:search');
  static const trash = RebuildGroup('notes:trash');
}

abstract class EditorGroups {
  static const content = RebuildGroup('editor:content');
  static const stats = RebuildGroup('editor:stats');
  static const status = RebuildGroup('editor:status');
}

abstract class SettingsGroups {
  static const viewMode = RebuildGroup('settings:viewMode');
  static const sort = RebuildGroup('settings:sort');
}
