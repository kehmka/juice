import 'package:juice/juice.dart';

class LoadDashboardEvent extends EventBase {
  LoadDashboardEvent() : super(groupsToRebuild: {'dashboard:stats', 'dashboard:activity'});
}

class RefreshStatsEvent extends EventBase {
  RefreshStatsEvent() : super(groupsToRebuild: {'dashboard:stats'});
}
