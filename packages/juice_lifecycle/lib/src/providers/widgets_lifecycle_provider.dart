import 'dart:async';

import 'package:flutter/widgets.dart';

import '../lifecycle_provider.dart';

/// Default [LifecycleProvider] backed by Flutter's `AppLifecycleListener`.
///
/// Deliberately logic-light: it only maps `AppLifecycleState` to [AppLifecycle]
/// and forwards changes. All behavior lives in `LifecycleBloc`, which is tested
/// with a fake provider — this adapter is verified by inspection and a one-time
/// in-app run.
class WidgetsLifecycleProvider implements LifecycleProvider {
  final _controller = StreamController<AppLifecycle>.broadcast();
  late final AppLifecycleListener _listener;
  AppLifecycle _current;

  WidgetsLifecycleProvider()
      : _current = _map(WidgetsBinding.instance.lifecycleState) {
    _listener = AppLifecycleListener(
      onStateChange: (state) {
        _current = _mapState(state);
        _controller.add(_current);
      },
    );
  }

  @override
  Stream<AppLifecycle> get changes => _controller.stream;

  @override
  AppLifecycle get current => _current;

  @override
  Future<void> dispose() async {
    _listener.dispose();
    await _controller.close();
  }

  static AppLifecycle _map(AppLifecycleState? state) =>
      state == null ? AppLifecycle.resumed : _mapState(state);

  static AppLifecycle _mapState(AppLifecycleState state) => switch (state) {
        AppLifecycleState.resumed => AppLifecycle.resumed,
        AppLifecycleState.inactive => AppLifecycle.inactive,
        AppLifecycleState.paused => AppLifecycle.paused,
        AppLifecycleState.detached => AppLifecycle.detached,
        AppLifecycleState.hidden => AppLifecycle.hidden,
      };
}
