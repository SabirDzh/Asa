import 'package:flutter/material.dart';

import 'scale_utils.dart';

/// Centers content and limits its width on large screens.
///
/// - < 600 logical pixels: full width, normal phone layout.
/// - 600–900: max width 600, centered.
/// - > 900: max width 800, centered.
class ResponsiveCenter extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;

  const ResponsiveCenter({required this.child, this.padding, super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Breakpoints describe the physical viewport, not the virtual canvas
        // used by the optional app-scale transform. Otherwise increasing the
        // UI scale on a tablet can incorrectly switch it to phone layout.
        final viewportWidth =
            AppScaleViewport.maybeOf(context)?.width ?? constraints.maxWidth;
        final double maxWidth;
        final EdgeInsets effectivePadding;

        if (viewportWidth > 900) {
          maxWidth = 800;
          effectivePadding =
              padding ?? const EdgeInsets.symmetric(horizontal: 32);
        } else if (viewportWidth > 600) {
          maxWidth = 600;
          effectivePadding =
              padding ?? const EdgeInsets.symmetric(horizontal: 24);
        } else {
          maxWidth = constraints.maxWidth.toDouble();
          effectivePadding =
              padding ?? const EdgeInsets.symmetric(horizontal: 0);
        }

        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Padding(padding: effectivePadding, child: child),
          ),
        );
      },
    );
  }
}
