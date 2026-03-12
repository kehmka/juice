import 'package:juice/juice.dart';
import 'analytics_state.dart';

class LoadAnalyticsEvent extends EventBase {
  LoadAnalyticsEvent() : super(groupsToRebuild: {'analytics:charts'});
}

class FilterDataEvent extends EventBase {
  final DateRange dateRange;
  FilterDataEvent({required this.dateRange})
      : super(groupsToRebuild: {'analytics:charts', 'analytics:filters'});
}
