import 'package:juice/juice.dart';

/// State for the source bloc in the relay demo.
/// Tracks a counter value and whether an async operation is in progress.
class SourceState extends BlocState {
  final int counter;
  final bool isProcessing;
  final String? errorMessage;

  SourceState({
    required this.counter,
    this.isProcessing = false,
    this.errorMessage,
  });

  SourceState copyWith({
    int? counter,
    bool? isProcessing,
    String? errorMessage,
    bool clearError = false,
  }) {
    return SourceState(
      counter: counter ?? this.counter,
      isProcessing: isProcessing ?? this.isProcessing,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  String toString() =>
      'SourceState(counter: $counter, isProcessing: $isProcessing, error: $errorMessage)';
}
