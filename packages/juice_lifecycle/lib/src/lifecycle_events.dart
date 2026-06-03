import 'package:juice/juice.dart';

import 'lifecycle_config.dart';
import 'lifecycle_provider.dart';

/// Base class for lifecycle events.
abstract class LifecycleEvent extends EventBase {
  @override
  String toString() => runtimeType.toString();
}

/// Configure the provider and start listening.
class InitializeLifecycleEvent extends LifecycleEvent {
  final LifecycleConfig config;
  InitializeLifecycleEvent({required this.config});
}

/// Internal: the app lifecycle phase changed.
class LifecycleChangedEvent extends LifecycleEvent {
  final AppLifecycle lifecycle;
  LifecycleChangedEvent(this.lifecycle);
}
