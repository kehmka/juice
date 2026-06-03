import 'lifecycle_provider.dart';
import 'providers/widgets_lifecycle_provider.dart';

/// Configuration for [LifecycleBloc].
class LifecycleConfig {
  /// The lifecycle source. Defaults to [WidgetsLifecycleProvider].
  ///
  /// Pass a fake here in tests to drive phases without a real binding.
  final LifecycleProvider provider;

  LifecycleConfig({LifecycleProvider? provider})
      : provider = provider ?? WidgetsLifecycleProvider();
}
