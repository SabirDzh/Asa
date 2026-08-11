import 'package:flutter/material.dart';

/// Multiplier applied to direct drag/swipe offsets for a faster scroll feel.
const double kScrollSensitivityMultiplier = 1.35;

/// Keeps the platform's normal scroll physics while applying a modest
/// sensitivity boost to direct user drags.
class FastScrollPhysics extends ScrollPhysics {
  const FastScrollPhysics({super.parent});

  @override
  FastScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return FastScrollPhysics(parent: buildParent(ancestor));
  }

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) {
    return super.applyPhysicsToUserOffset(
      position,
      offset * kScrollSensitivityMultiplier,
    );
  }
}

/// Global scroll behavior used by the app shell.
///
/// Scrollables with their own explicit physics (for example the time picker)
/// keep those physics. The behavior affects ordinary lists and scroll views
/// that use the platform default physics.
class FastScrollBehavior extends MaterialScrollBehavior {
  const FastScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return FastScrollPhysics(parent: super.getScrollPhysics(context));
  }
}
