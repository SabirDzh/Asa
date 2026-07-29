import 'package:flutter/material.dart';

import 'theme.dart';

/// Mixin for a [State] that wants to hide/show a floating widget when the
/// user scrolls down/up.
///
/// The widget starts visible. After a downward scroll larger than
/// [AppTheme.scrollHideThreshold] it becomes hidden; after an upward scroll
/// larger than the threshold it becomes visible again.
mixin ScrollHideMixin<T extends StatefulWidget> on State<T> {
  bool _fabVisible = true;

  bool get fabVisible => _fabVisible;

  /// Call this from a [NotificationListener<ScrollNotification>].
  ///
  /// Returns `true` if the notification has been handled and should not
  /// bubble further. Currently always returns `false` to allow bubbling.
  bool handleScrollNotification(ScrollNotification notification) {
    if (notification is! ScrollUpdateNotification) return false;
    final delta = notification.scrollDelta ?? 0;
    if (delta > AppTheme.scrollHideThreshold) {
      if (_fabVisible) setState(() => _fabVisible = false);
    } else if (delta < -AppTheme.scrollHideThreshold) {
      if (!_fabVisible) setState(() => _fabVisible = true);
    }
    return false;
  }
}
