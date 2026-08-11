import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:asa/core/fast_scroll.dart';

void main() {
  test('uses a modest scroll sensitivity boost', () {
    expect(kScrollSensitivityMultiplier, greaterThan(1.0));
    expect(kScrollSensitivityMultiplier, 1.35);
  });

  test('applies the sensitivity multiplier to in-range drag offsets', () {
    const physics = FastScrollPhysics();
    final metrics = FixedScrollMetrics(
      minScrollExtent: 0,
      maxScrollExtent: 1000,
      pixels: 200,
      viewportDimension: 500,
      axisDirection: AxisDirection.down,
      devicePixelRatio: 1,
    );

    expect(physics.applyPhysicsToUserOffset(metrics, 10), 13.5);
  });

  test('preserves the parent physics when applying fast physics', () {
    const physics = FastScrollPhysics(parent: ClampingScrollPhysics());
    final applied = physics.applyTo(const BouncingScrollPhysics());

    expect(applied, isA<FastScrollPhysics>());

    var parent = applied.parent;
    var hasBouncingParent = false;
    while (parent != null) {
      if (parent is BouncingScrollPhysics) {
        hasBouncingParent = true;
        break;
      }
      parent = parent.parent;
    }
    expect(hasBouncingParent, isTrue);
  });

  test('provides fast physics through the app scroll behavior', () {
    const behavior = FastScrollBehavior();
    final physics = behavior.getScrollPhysics(_TestBuildContext());

    expect(physics, isA<FastScrollPhysics>());
  });
}

/// The behavior only needs a BuildContext argument for this unit-level test.
class _TestBuildContext implements BuildContext {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
