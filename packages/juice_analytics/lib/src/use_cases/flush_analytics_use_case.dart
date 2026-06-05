import 'package:juice/juice.dart';

import '../analytics_bloc.dart';
import '../analytics_events.dart';

/// Handles [FlushAnalyticsEvent] — flush buffered events across sinks.
class FlushAnalyticsUseCase extends BlocUseCase<AnalyticsBloc, FlushAnalyticsEvent> {
  @override
  Future<void> execute(FlushAnalyticsEvent event) async {
    await bloc.fanOut((s) => s.flush());
  }
}
