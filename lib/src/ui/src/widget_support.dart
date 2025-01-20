import 'package:juice/juice.dart';

/// Special marker for indicating rebuild-all behavior
const String _alwaysRebuild = '*';

/// Special marker for indicating opt-out behavior
const String _optOut = '-';

/// Constant with special meaning in the rebuild system:
///
/// When an event includes this in its rebuild groups, it will trigger rebuilds
/// in all widgets that haven't opted out using [optOutOfRebuilds].
///
/// For events (emitUpdate):
/// - Makes all participating widgets rebuild
/// ```dart
/// emitUpdate(groupsToRebuild: rebuildAlways);
/// ```
///
/// For widgets:
/// - Makes widget participate in all rebuilds
/// ```dart
/// class MyWidget extends StatelessJuiceWidget<MyBloc> {
///   MyWidget({super.key, super.groups = rebuildAlways});
/// }
/// ```
const Set<String> rebuildAlways = {_alwaysRebuild};

/// When a widget specifies this in its rebuild groups, it will never rebuild
/// in response to bloc events, regardless of the event's rebuild groups.
///
/// Example:
/// ```dart
/// class StaticWidget extends StatelessJuiceWidget<MyBloc> {
///   StaticWidget({super.key, super.groups = optOutOfRebuilds});
/// }
/// ```
const Set<String> optOutOfRebuilds = {_optOut};

/// Determines whether a widget should skip rebuilding in response to an event.
///
/// This function implements the rebuild control logic:
/// 1. If the widget has opted out using [optOutOfRebuilds], always deny rebuild
/// 2. Otherwise, check if the event's rebuild groups include either:
///    - [rebuildAlways]
///    - Any group specified by the widget
///
/// Parameters:
/// * [event] - The event that triggered the potential rebuild
/// * [key] - The widget's key (reserved for future use)
/// * [rebuildGroups] - The set of rebuild groups specified by the widget
///
/// Returns true if the widget should skip rebuilding, false if it should rebuild.
bool denyRebuild({
  EventBase? event,
  Key? key,
  required Set<String> rebuildGroups,
}) {
  if (rebuildGroups.contains(_optOut)) {
    return true;
  }
  return !_isInRebuildGroup(event, rebuildGroups);
}

/// Internal helper to check if a widget's rebuild groups intersect with an event's groups.
///
/// Returns true if either:
/// - The event specifies [rebuildAlways]
/// - The event's rebuild groups overlap with the widget's rebuild groups
///
/// If the event has no rebuild groups specified, returns false (no rebuild).
bool _isInRebuildGroup(EventBase? event, Set<String> rebuildGroups) {
  if (event?.groupsToRebuild == null) return false;
  final groups = event!.groupsToRebuild!;
  return groups.contains(_alwaysRebuild) ||
      groups.intersection(rebuildGroups).isNotEmpty;
}
