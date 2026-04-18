import 'package:juice/juice.dart';
import '../rebuild_groups.dart';
import 'settings_state.dart';

class LoadSettingsEvent extends EventBase {
  LoadSettingsEvent()
      : super(
            groupsToRebuild:
                {SettingsGroups.viewMode, SettingsGroups.sort}.toStringSet());
}

class ToggleViewModeEvent extends EventBase {
  ToggleViewModeEvent()
      : super(groupsToRebuild: {SettingsGroups.viewMode}.toStringSet());
}

class ChangeSortOrderEvent extends EventBase {
  final SortOrder sortOrder;

  ChangeSortOrderEvent({required this.sortOrder})
      : super(groupsToRebuild: {SettingsGroups.sort}.toStringSet());
}
