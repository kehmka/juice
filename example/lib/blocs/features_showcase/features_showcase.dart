/// Features Showcase - Demonstrates new Juice framework features.
///
/// This example showcases:
/// - BlocTester for simplified testing
/// - JuiceException hierarchy (NetworkException, ValidationException, etc.)
/// - FailureStatus with error and stackTrace context
/// - sendAndWait helper for awaiting event completion
/// - emitUpdate with skipIfSame for state deduplication
/// - JuiceSelector for optimized widget rebuilds
/// - Memory leak detection with LeakDetector
library features_showcase;

export 'features_showcase_bloc.dart';
export 'features_showcase_state.dart';
export 'features_showcase_events.dart';
