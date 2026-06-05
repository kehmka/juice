import 'package:juice/juice.dart';

import '../location_bloc.dart';
import '../location_events.dart';

/// Handles [InitializeLocationEvent] — store the config.
class InitializeLocationUseCase
    extends BlocUseCase<LocationBloc, InitializeLocationEvent> {
  @override
  Future<void> execute(InitializeLocationEvent event) async {
    bloc.configure(event.config);
  }
}
