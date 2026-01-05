import 'package:flutter/material.dart';
import 'package:juice/juice.dart';

import '../features_showcase.dart';

/// Page that showcases the new Juice framework features.
///
/// Demonstrates:
/// - JuiceSelector for optimized widget rebuilds
/// - sendAndWait for awaiting event completion
/// - FailureStatus with error context display
/// - JuiceException typed error handling
class FeaturesShowcasePage extends StatelessWidget {
  const FeaturesShowcasePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Features Showcase'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              BlocScope.get<FeaturesShowcaseBloc>().send(ShowcaseResetEvent());
            },
            tooltip: 'Reset',
          ),
        ],
      ),
      body: const SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _FeatureSection(
              title: 'JuiceSelector - Optimized Rebuilds',
              description:
                  'Only rebuilds when selected state changes. Watch the rebuild counters!',
              child: _CounterSection(),
            ),
            SizedBox(height: 24),
            _FeatureSection(
              title: 'sendAndWait & JuiceException',
              description:
                  'Demonstrates async operations with typed exceptions.',
              child: _ApiSection(),
            ),
            SizedBox(height: 24),
            _FeatureSection(
              title: 'ValidationException',
              description: 'Type-safe validation with field information.',
              child: _ValidationSection(),
            ),
            SizedBox(height: 24),
            _FeatureSection(
              title: 'FailureStatus Error Context',
              description: 'Errors include full context for debugging.',
              child: _ErrorDisplay(),
            ),
            SizedBox(height: 24),
            _FeatureSection(
              title: 'Activity Log',
              description: 'Shows all state changes in real-time.',
              child: _ActivityLog(),
            ),
          ],
        ),
      ),
    );
  }
}

/// Section wrapper with title and description.
class _FeatureSection extends StatelessWidget {
  final String title;
  final String description;
  final Widget child;

  const _FeatureSection({
    required this.title,
    required this.description,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              description,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[600],
                  ),
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

/// Counter section using JuiceSelector for optimized rebuilds.
class _CounterSection extends StatelessWidget {
  const _CounterSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // This JuiceSelector ONLY rebuilds when counter changes
            JuiceSelector<FeaturesShowcaseBloc, FeaturesShowcaseState, int>(
              selector: (state) => state.counter,
              builder: (context, counter) {
                return _RebuildTracker(
                  label: 'Counter',
                  child: Text(
                    '$counter',
                    style: Theme.of(context).textTheme.displayMedium,
                  ),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton.icon(
              onPressed: () {
                BlocScope.get<FeaturesShowcaseBloc>().send(ShowcaseDecrementEvent());
              },
              icon: const Icon(Icons.remove),
              label: const Text('Decrement'),
            ),
            const SizedBox(width: 16),
            ElevatedButton.icon(
              onPressed: () {
                BlocScope.get<FeaturesShowcaseBloc>().send(ShowcaseIncrementEvent());
              },
              icon: const Icon(Icons.add),
              label: const Text('Increment'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // This JuiceSelector ONLY rebuilds when message changes
        JuiceSelector<FeaturesShowcaseBloc, FeaturesShowcaseState, String>(
          selector: (state) => state.message,
          builder: (context, message) {
            return _RebuildTracker(
              label: 'Message',
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
            );
          },
        ),
      ],
    );
  }
}

/// API section demonstrating sendAndWait and NetworkException.
class _ApiSection extends StatefulWidget {
  const _ApiSection();

  @override
  State<_ApiSection> createState() => _ApiSectionState();
}

class _ApiSectionState extends State<_ApiSection> {
  bool _isWaitingForResult = false;
  String _resultMessage = '';

  Future<void> _callApi({required bool shouldFail}) async {
    setState(() {
      _isWaitingForResult = true;
      _resultMessage = '';
    });

    final bloc = BlocScope.get<FeaturesShowcaseBloc>();

    // Using sendAndWait to await the result
    final status = await bloc.sendAndWait(
      SimulateApiCallEvent(shouldFail: shouldFail),
    );

    setState(() {
      _isWaitingForResult = false;
      if (status is FailureStatus<FeaturesShowcaseState>) {
        final failure = status;
        final error = failure.error;
        if (error is NetworkException) {
          _resultMessage =
              'NetworkException: ${error.message} (status: ${error.statusCode})';
        } else {
          _resultMessage = 'Error: ${failure.error}';
        }
      } else {
        _resultMessage = 'Success!';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Show loading state using JuiceSelector
        JuiceSelector<FeaturesShowcaseBloc, FeaturesShowcaseState, bool>(
          selector: (state) => state.isLoading,
          builder: (context, isLoading) {
            if (isLoading) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              );
            }
            return const SizedBox.shrink();
          },
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: _isWaitingForResult
                  ? null
                  : () => _callApi(shouldFail: false),
              child: const Text('Successful API Call'),
            ),
            const SizedBox(width: 16),
            ElevatedButton(
              onPressed: _isWaitingForResult
                  ? null
                  : () => _callApi(shouldFail: true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
              ),
              child: const Text('Failing API Call'),
            ),
          ],
        ),
        if (_resultMessage.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(
              'sendAndWait result: $_resultMessage',
              style: TextStyle(
                color: _resultMessage.contains('Error') ||
                        _resultMessage.contains('Exception')
                    ? Colors.red
                    : Colors.green,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        const SizedBox(height: 8),
        // Show API call count
        JuiceSelector<FeaturesShowcaseBloc, FeaturesShowcaseState, int>(
          selector: (state) => state.apiCallCount,
          builder: (context, count) {
            return Text('Successful API calls: $count');
          },
        ),
      ],
    );
  }
}

/// Validation section demonstrating ValidationException.
class _ValidationSection extends StatefulWidget {
  const _ValidationSection();

  @override
  State<_ValidationSection> createState() => _ValidationSectionState();
}

class _ValidationSectionState extends State<_ValidationSection> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: _controller,
          decoration: const InputDecoration(
            labelText: 'Enter a message (3-100 chars)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: () {
            BlocScope.get<FeaturesShowcaseBloc>()
                .send(ValidateInputEvent(_controller.text));
          },
          child: const Text('Validate & Update Message'),
        ),
      ],
    );
  }
}

/// Error display showing FailureStatus error context.
class _ErrorDisplay extends StatelessWidget {
  const _ErrorDisplay();

  @override
  Widget build(BuildContext context) {
    return JuiceBuilder<FeaturesShowcaseBloc>(
      groups: const {'error', 'status'},
      builder: (context, bloc, status) {
        final hasError = bloc.state.lastError != null;

        if (!hasError && status is! FailureStatus) {
          return const Text(
            'No errors. Try the failing API call or invalid validation.',
            style: TextStyle(color: Colors.green),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (bloc.state.lastError != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.error, color: Colors.red),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            bloc.state.lastError!,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                      ],
                    ),
                    if (status is FailureStatus && status.error != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Error type: ${status.error.runtimeType}',
                        style: TextStyle(
                          color: Colors.red.shade700,
                          fontSize: 12,
                        ),
                      ),
                      if (status.error is JuiceException)
                        Text(
                          'Retryable: ${(status.error as JuiceException).isRetryable}',
                          style: TextStyle(
                            color: Colors.red.shade700,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () {
                BlocScope.get<FeaturesShowcaseBloc>().send(ClearErrorEvent());
              },
              icon: const Icon(Icons.clear),
              label: const Text('Clear Error'),
            ),
          ],
        );
      },
    );
  }
}

/// Activity log showing all state changes.
class _ActivityLog extends StatelessWidget {
  const _ActivityLog();

  @override
  Widget build(BuildContext context) {
    return JuiceSelector<FeaturesShowcaseBloc, FeaturesShowcaseState,
        List<String>>(
      selector: (state) => state.activityLog,
      builder: (context, log) {
        if (log.isEmpty) {
          return const Text('No activity yet.');
        }

        return Container(
          height: 150,
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
          ),
          child: ListView.builder(
            reverse: true,
            padding: const EdgeInsets.all(8),
            itemCount: log.length,
            itemBuilder: (context, index) {
              final reversedIndex = log.length - 1 - index;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  '${reversedIndex + 1}. ${log[reversedIndex]}',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

/// Widget that tracks rebuilds for demonstration.
class _RebuildTracker extends StatefulWidget {
  final String label;
  final Widget child;

  const _RebuildTracker({
    required this.label,
    required this.child,
  });

  @override
  State<_RebuildTracker> createState() => _RebuildTrackerState();
}

class _RebuildTrackerState extends State<_RebuildTracker> {
  int _rebuildCount = 0;

  @override
  Widget build(BuildContext context) {
    _rebuildCount++;
    return Column(
      children: [
        widget.child,
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.blue.shade100,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            '${widget.label} rebuilds: $_rebuildCount',
            style: TextStyle(
              fontSize: 10,
              color: Colors.blue.shade800,
            ),
          ),
        ),
      ],
    );
  }
}
