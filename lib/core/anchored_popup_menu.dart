import 'dart:math' as math;

import 'package:flutter/material.dart';

/// An item displayed by [showAnchoredPopupMenu].
class AnchoredPopupMenuItem<T> extends StatelessWidget {
  final T value;
  final Widget child;

  const AnchoredPopupMenuItem({
    super.key,
    required this.value,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.of(context).pop(value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: child,
      ),
    );
  }
}

/// Shows a popup menu anchored to [anchorContext].
///
/// The menu is placed exactly [gap] logical pixels below the anchor when it
/// fits. If it does not fit below, it is placed above the anchor with the same
/// gap. The route measures the real menu height instead of estimating item
/// heights, so the rule remains correct for localized labels and different
/// menu contents.
Future<T?> showAnchoredPopupMenu<T>({
  required BuildContext context,
  required BuildContext anchorContext,
  required List<AnchoredPopupMenuItem<T>> items,
  required Color color,
  required ShapeBorder shape,
  Key? menuKey,
  double gap = 6.0,
}) {
  final navigator = Navigator.of(anchorContext);
  final overlay = navigator.overlay;
  final anchor = anchorContext.findRenderObject() as RenderBox?;
  final overlayBox = overlay?.context.findRenderObject() as RenderBox?;

  if (overlay == null ||
      anchor == null ||
      overlayBox == null ||
      !anchor.hasSize) {
    return Future<T?>.value(null);
  }

  final anchorTopLeft = anchor.localToGlobal(Offset.zero, ancestor: overlayBox);
  final anchorBottomRight = anchor.localToGlobal(
    anchor.size.bottomRight(Offset.zero),
    ancestor: overlayBox,
  );
  final anchorRect = Rect.fromPoints(anchorTopLeft, anchorBottomRight);
  final localizations = MaterialLocalizations.of(anchorContext);

  return navigator.push<T>(
    _AnchoredPopupMenuRoute<T>(
      anchorRect: anchorRect,
      items: items,
      color: color,
      shape: shape,
      menuKey: menuKey,
      gap: gap,
      barrierText: localizations.modalBarrierDismissLabel,
    ),
  );
}

class _AnchoredPopupMenuRoute<T> extends PopupRoute<T> {
  final Rect anchorRect;
  final List<AnchoredPopupMenuItem<T>> items;
  final Color color;
  final ShapeBorder shape;
  final Key? menuKey;
  final double gap;
  final String barrierText;

  _AnchoredPopupMenuRoute({
    required this.anchorRect,
    required this.items,
    required this.color,
    required this.shape,
    required this.menuKey,
    required this.gap,
    required this.barrierText,
  });

  @override
  Duration get transitionDuration => const Duration(milliseconds: 120);

  @override
  bool get barrierDismissible => true;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => barrierText;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final mediaQuery = MediaQuery.of(context);
    return CustomSingleChildLayout(
      delegate: _AnchoredPopupMenuLayout(
        anchorRect: anchorRect,
        gap: gap,
        viewPadding: mediaQuery.padding,
      ),
      child: Material(
        key: menuKey,
        color: color,
        elevation: 8,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: IntrinsicWidth(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 112, maxWidth: 280),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: ListBody(children: items),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
        alignment: Alignment.topRight,
        child: child,
      ),
    );
  }
}

class _AnchoredPopupMenuLayout extends SingleChildLayoutDelegate {
  final Rect anchorRect;
  final double gap;
  final EdgeInsets viewPadding;

  const _AnchoredPopupMenuLayout({
    required this.anchorRect,
    required this.gap,
    required this.viewPadding,
  });

  static const double _screenPadding = 8.0;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints.loose(constraints.biggest).deflate(
      EdgeInsets.fromLTRB(
        _screenPadding + viewPadding.left,
        _screenPadding + viewPadding.top,
        _screenPadding + viewPadding.right,
        _screenPadding + viewPadding.bottom,
      ),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final screenLeft = _screenPadding + viewPadding.left;
    final screenTop = _screenPadding + viewPadding.top;
    final screenRight = size.width - _screenPadding - viewPadding.right;
    final screenBottom = size.height - _screenPadding - viewPadding.bottom;

    final below = anchorRect.bottom + gap;
    final above = anchorRect.top - gap - childSize.height;
    final fitsBelow = below + childSize.height <= screenBottom;
    final fitsAbove = above >= screenTop;

    final double y;
    if (fitsBelow) {
      y = below;
    } else if (fitsAbove) {
      y = above;
    } else {
      // If the menu is taller than the available space on both sides, prefer
      // the side with more room while keeping it within the safe viewport.
      final availableBelow = screenBottom - below;
      final availableAbove = anchorRect.top - gap - screenTop;
      final preferred = availableAbove > availableBelow ? above : below;
      y =
          preferred
              .clamp(
                screenTop,
                math.max(screenTop, screenBottom - childSize.height),
              )
              .toDouble();
    }

    final preferredX = anchorRect.right - childSize.width;
    final x =
        preferredX
            .clamp(
              screenLeft,
              math.max(screenLeft, screenRight - childSize.width),
            )
            .toDouble();

    return Offset(x, y);
  }

  @override
  bool shouldRelayout(covariant _AnchoredPopupMenuLayout oldDelegate) {
    return anchorRect != oldDelegate.anchorRect ||
        gap != oldDelegate.gap ||
        viewPadding != oldDelegate.viewPadding;
  }
}
