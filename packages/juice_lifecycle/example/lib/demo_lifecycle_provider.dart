import 'dart:async';

import 'package:juice_lifecycle/juice_lifecycle.dart';

/// A self-contained [LifecycleProvider] that cycles through phases on a timer,
/// so the demo shows transitions without backgrounding the app.
///
/// Implementing [LifecycleProvider] is the framework's intended seam — the same
/// pattern the real `WidgetsLifecycleProvider` uses.
class DemoLifecycleProvider implements LifecycleProvider {
  final _ctrl = StreamController<AppLifecycle>.broadcast();
  Timer? _timer;

  static const _cycle = [
    AppLifecycle.resumed,
    AppLifecycle.inactive,
    AppLifecycle.paused,
  ];
  int _i = 0;

  DemoLifecycleProvider() {
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      _i = (_i + 1) % _cycle.length;
      _ctrl.add(_cycle[_i]);
    });
  }

  @override
  Stream<AppLifecycle> get changes => _ctrl.stream;

  @override
  AppLifecycle get current => _cycle[_i];

  @override
  Future<void> dispose() async {
    _timer?.cancel();
    await _ctrl.close();
  }
}
