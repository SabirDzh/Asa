import 'package:flutter/material.dart';

/// Minimum allowed UI scale.
const double kMinAppScale = 0.8;

/// Absolute maximum UI scale (used only for persistence and custom input;
/// the runtime cap is determined by [getAdaptiveMaxScale]).
const double kAbsoluteMaxAppScale = 1.3;

/// Returns the maximum recommended UI scale for the current screen.
///
/// The cap is based on the shortest logical side of the screen (i.e. the
/// smallest of width/height). Smaller devices get a lower cap so that the
/// scaled UI still fits without overflowing.
///
/// Breakpoints:
///   - shortestSide < 360 dp  → max 1.1
///   - shortestSide < 400 dp  → max 1.2
///   - otherwise              → max 1.3
///
/// The user's preferred scale is preserved; this is only a runtime cap.
double getAdaptiveMaxScale(BuildContext context) {
  final shortestSide = MediaQuery.sizeOf(context).shortestSide;
  if (shortestSide < 360) return 1.1;
  if (shortestSide < 400) return 1.2;
  return 1.3;
}
