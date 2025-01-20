import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class JuiceExceptionWidget extends StatelessWidget {
  final Exception exception;
  final StackTrace stackTrace;

  const JuiceExceptionWidget({
    super.key,
    required this.exception,
    required this.stackTrace,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Scaffold(
        backgroundColor:
            theme.colorScheme.errorContainer.withValues(alpha: 0.1),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          actions: [
            IconButton(
              icon: const Icon(Icons.copy),
              onPressed: () {
                final errorText =
                    'Exception:\n${exception.toString()}\n\nStackTrace:\n$stackTrace';
                Clipboard.setData(ClipboardData(text: errorText));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Error details copied to clipboard')),
                );
              },
            ),
          ],
        ),
        body: CustomScrollView(
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 64,
                      color: theme.colorScheme.error,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      "Uncaught Exception",
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.error,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    _ErrorCard(
                      title: 'Error Details',
                      content: exception.toString(),
                      theme: theme,
                    ),
                    const SizedBox(height: 16),
                    _ErrorCard(
                      title: 'Stack Trace',
                      content: _formatStackTrace(stackTrace.toString()),
                      theme: theme,
                      maxLines: null,
                    ),
                    const Spacer(),
                    OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Dismiss'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatStackTrace(String stackTrace) {
    final lines = stackTrace.split('\n');
    return lines.map((line) => line.trim()).join('\n');
  }
}

class _ErrorCard extends StatelessWidget {
  final String title;
  final String content;
  final ThemeData theme;
  final int? maxLines;

  const _ErrorCard({
    required this.title,
    required this.content,
    required this.theme,
    this.maxLines,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            SelectableText(
              content,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFamily: 'monospace',
              ),
              maxLines: maxLines,
            ),
          ],
        ),
      ),
    );
  }
}
