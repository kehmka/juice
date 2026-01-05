import 'package:juice/juice.dart';

/// State for the features showcase example.
///
/// Demonstrates:
/// - State used with JuiceSelector for optimized rebuilds
/// - Error context stored from FailureStatus
class FeaturesShowcaseState extends BlocState {
  final int counter;
  final String message;
  final bool isLoading;
  final String? lastError;
  final int apiCallCount;
  final List<String> activityLog;

  const FeaturesShowcaseState({
    this.counter = 0,
    this.message = 'Welcome to the Features Showcase!',
    this.isLoading = false,
    this.lastError,
    this.apiCallCount = 0,
    this.activityLog = const [],
  });

  FeaturesShowcaseState copyWith({
    int? counter,
    String? message,
    bool? isLoading,
    String? lastError,
    bool clearError = false,
    int? apiCallCount,
    List<String>? activityLog,
  }) {
    return FeaturesShowcaseState(
      counter: counter ?? this.counter,
      message: message ?? this.message,
      isLoading: isLoading ?? this.isLoading,
      lastError: clearError ? null : (lastError ?? this.lastError),
      apiCallCount: apiCallCount ?? this.apiCallCount,
      activityLog: activityLog ?? this.activityLog,
    );
  }

  @override
  String toString() =>
      'FeaturesShowcaseState(counter: $counter, message: $message, isLoading: $isLoading, apiCallCount: $apiCallCount)';
}
