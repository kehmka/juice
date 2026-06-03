import 'package:juice/juice.dart';

import '../permissions_bloc.dart';
import '../permissions_events.dart';

/// Handles [OpenAppSettingsEvent] — open the OS settings page so the user can
/// change a permanently-denied permission.
class OpenAppSettingsUseCase
    extends BlocUseCase<PermissionsBloc, OpenAppSettingsEvent> {
  @override
  Future<void> execute(OpenAppSettingsEvent event) async {
    await bloc.provider.openSettings();
  }
}
