import 'package:flutter/material.dart';

/// Absolute minimum UI scale (used for persistence).
const double kAbsoluteMinAppScale = 0.8;

/// Absolute maximum UI scale (used for persistence and custom input).
const double kAbsoluteMaxAppScale = 1.3;

/// Range of allowed UI scale values for the current screen.
class AdaptiveAppScaleRange {
  final double min;
  final double max;

  const AdaptiveAppScaleRange({required this.min, required this.max});
}

/// Returns the adaptive min/max UI scale for the current screen.
///
/// The range is based on the shortest logical side of the screen. Smaller
/// devices get a higher minimum to keep touch targets and text readable,
/// and a lower maximum to prevent overflow. Larger devices get the full
/// 0.8 – 1.3 range.
///
/// Breakpoints:
///   - shortestSide < 360 dp  → min 0.95, max 1.1
///   - shortestSide < 400 dp  → min 0.85, max 1.2
///   - otherwise              → min 0.80, max 1.3
///
/// The user's preferred scale is preserved; this is only a runtime cap.
AdaptiveAppScaleRange getAdaptiveScaleRange(BuildContext context) {
  final shortestSide = MediaQuery.sizeOf(context).shortestSide;
  if (shortestSide < 360) {
    return const AdaptiveAppScaleRange(min: 0.95, max: 1.1);
  }
  if (shortestSide < 400) {
    return const AdaptiveAppScaleRange(min: 0.85, max: 1.2);
  }
  return const AdaptiveAppScaleRange(min: 0.80, max: 1.3);
}

/// Returns the effective UI scale for a saved [scale] on the current screen.
///
/// This applies the adaptive [getAdaptiveScaleRange] limits without modifying
/// the persisted value.
double effectiveAppScale(BuildContext context, double scale) {
  final range = getAdaptiveScaleRange(context);
  return scale.clamp(range.min, range.max);
}
