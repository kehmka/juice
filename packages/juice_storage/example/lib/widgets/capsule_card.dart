import 'package:flutter/material.dart';
import '../demo_entry.dart';

/// A card displaying a stored entry with TTL countdown.
///
/// Shows:
/// - Backend type and key
/// - Stored value
/// - TTL progress bar with countdown
/// - Read/Delete actions
class CapsuleCard extends StatelessWidget {
  const CapsuleCard({
    super.key,
    required this.entry,
    required this.now,
    this.onRead,
    this.onDelete,
  });

  final DemoEntry entry;
  final DateTime now;
  final VoidCallback? onRead;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final expired = entry.isExpired(now);
    final progress = entry.progress(now);
    final remaining = entry.secondsRemaining(now);

    // Color based on expiry status
    final borderColor = expired
        ? theme.colorScheme.error
        : progress != null && progress < 0.3
            ? theme.colorScheme.tertiary
            : theme.colorScheme.outlineVariant;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          width: expired ? 2 : 1,
          color: borderColor,
        ),
        color: expired
            ? theme.colorScheme.errorContainer.withValues(alpha: 0.3)
            : theme.colorScheme.surfaceContainerLow,
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                // Backend badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    color: _backendColor(entry.backend).withValues(alpha: 0.2),
                  ),
                  child: Text(
                    entry.backend.name.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: _backendColor(entry.backend),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Key
                Expanded(
                  child: Text(
                    entry.key,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Actions
                IconButton(
                  tooltip: 'Read (triggers lazy eviction if expired)',
                  onPressed: onRead,
                  icon: Icon(
                    Icons.visibility,
                    size: 20,
                    color: expired ? theme.colorScheme.error : null,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  tooltip: 'Delete',
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline, size: 20),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Value
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: theme.colorScheme.surfaceContainerHighest,
              ),
              child: Text(
                entry.value,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),

            const SizedBox(height: 8),

            // TTL progress or "No TTL" label
            if (entry.ttl != null) ...[
              Row(
                children: [
                  // Progress bar
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress ?? 0,
                        minHeight: 8,
                        backgroundColor:
                            theme.colorScheme.surfaceContainerHighest,
                        valueColor: AlwaysStoppedAnimation(
                          expired
                              ? theme.colorScheme.error
                              : progress != null && progress < 0.3
                                  ? theme.colorScheme.tertiary
                                  : theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Countdown
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 150),
                    child: SizedBox(
                      width: 64,
                      key: ValueKey(expired ? 'expired' : remaining),
                      child: Text(
                        expired ? 'EXPIRED' : '${remaining}s',
                        textAlign: TextAlign.end,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: expired
                              ? theme.colorScheme.error
                              : progress != null && progress < 0.3
                                  ? theme.colorScheme.tertiary
                                  : theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ] else ...[
              Row(
                children: [
                  Icon(
                    Icons.all_inclusive,
                    size: 14,
                    color: theme.colorScheme.outline,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'No TTL (never expires)',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _backendColor(DemoBackend backend) {
    return switch (backend) {
      DemoBackend.prefs => Colors.blue,
      DemoBackend.hive => Colors.amber.shade700,
      DemoBackend.secure => Colors.green,
      DemoBackend.sqlite => Colors.purple,
    };
  }
}
