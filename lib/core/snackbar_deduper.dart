import 'package:flutter/material.dart';

/// Deduplicates identical [SnackBar] messages so the user never sees
/// the same notification back-to-back. When the same text arrives again
/// before the previous bar has timed out, the current bar is replaced by
/// a single bar whose duration accumulates (N repeats = base × N seconds).
///
/// ## Usage
///
/// ```dart
/// SnackBarDeduper.show(context, 'Задачу нельзя перенести на главный экран');
/// ```
///
/// The helper hides the current bar if it carries the exact same message,
/// increments an internal counter, and shows a fresh bar with
/// `baseDuration × counter` so the user has time to read the notification
/// without being spammed.
class SnackBarDeduper {
  SnackBarDeduper._();

  static final Map<String, _Entry> _entries = {};

  /// Show a deduplicated snack bar with [message].
  ///
  /// If the same [message] is already visible, the current bar is replaced
  /// and the duration is extended proportionally.
  static void show(
    BuildContext context,
    String message, {
    Duration baseDuration = const Duration(seconds: 3),
    SnackBarBehavior behavior = SnackBarBehavior.fixed,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    final entry = _entries.putIfAbsent(message, () => _Entry());

    entry.count++;
    if (entry.count > 1) {
      messenger.hideCurrentSnackBar();
    }

    final duration = baseDuration * entry.count;

    messenger
        .showSnackBar(
          SnackBar(
            content: Text(message),
            duration: duration,
            behavior: behavior,
          ),
        )
        .closed
        .then((reason) {
          // Reset the counter only when the bar reaches its natural end.
          // If the bar was removed because a new one replaced it, keep the
          // accumulated count so the replacement bar shows the extended
          // duration.
          if (reason != SnackBarClosedReason.remove) {
            entry.count = 0;
          }
        });
  }
}

class _Entry {
  int count = 0;
}
