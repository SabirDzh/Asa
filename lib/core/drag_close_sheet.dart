import 'package:flutter/material.dart';

/// Wraps a bottom-sheet body so that pulling it down with a finger closes it,
/// even when the body contains a scrollable.
///
/// The framework's built-in drag-to-dismiss only works while the sheet content
/// has no scrollable that can win the vertical gesture arena. On Android a tall
/// scrollable sheet therefore cannot be closed by dragging at all. This wrapper
/// uses two complementary mechanisms:
///
///  * Raw pointer tracking on areas without a scrollable (headers, short
///    sheets) translates the sheet directly with the finger.
///  * When [trackScrollableDrag] is enabled, leading-edge
///    `OverscrollNotification`s from a tall clamped scrollable drive the same
///    translation, so pulling down at the top of a list closes the sheet too.
///
/// Pair this with `enableDrag: false` on [showModalBottomSheet] so the
/// framework's gesture detector does not double-move the sheet.
class DragToCloseSheet extends StatefulWidget {
  const DragToCloseSheet({
    super.key,
    required this.child,
    this.closeThreshold = 120,
    this.maxPullFraction = 0.5,
    this.springDuration = const Duration(milliseconds: 180),
    this.closeDuration = const Duration(milliseconds: 200),
    this.trackScrollableDrag = false,
  });

  /// How far (logical pixels) the sheet must be pulled before releasing closes
  /// it.
  final double closeThreshold;

  /// Maximum downward travel, as a fraction of the screen height.
  final double maxPullFraction;

  /// How long it takes the sheet to spring back after a short pull.
  final Duration springDuration;

  /// How long it takes the sheet to slide away before closing.
  final Duration closeDuration;

  /// Whether to translate the sheet while a clamped vertical scrollable at its
  /// top edge overscrolls (the Android pull-to-close pattern for tall sheets).
  final bool trackScrollableDrag;

  /// The sheet body. It should include the whole visible surface (background,
  /// rounded corners) because the sheet is translated as a single unit.
  final Widget child;

  @override
  State<DragToCloseSheet> createState() => _DragToCloseSheetState();
}

class _DragToCloseSheetState extends State<DragToCloseSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.springDuration,
  );

  double _scrollOffset = 0;
  bool _verticalDragActive = false;
  double _dragStartY = 0;
  double _dragStartScrollOffset = 0;

  bool _scrollDragActive = false;
  double _overscrollAccum = 0;
  bool _closing = false;
  double _maxPull = 0;

  double get _pullPx => _controller.value * _maxPull;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _maxPull = MediaQuery.sizeOf(context).height * widget.maxPullFraction;
  }

  void _setPull(double px) {
    final clamped = px.clamp(0.0, _maxPull);
    _controller.value = _maxPull == 0 ? 0 : clamped / _maxPull;
  }

  bool _handleScroll(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;

    // Notifications from nested scrollables (description previews, mention
    // lists, and attachment lists) must never drive the parent sheet. The
    // sheet only coordinates with its direct, primary scrollable.
    if (notification.depth != 0) return false;
    _scrollOffset = notification.metrics.pixels;
    if (!widget.trackScrollableDrag) return false;

    if (notification is ScrollStartNotification) {
      if (notification.dragDetails != null) {
        _scrollDragActive = true;
        _overscrollAccum = 0;
        _controller.stop();
      }
    } else if (notification is OverscrollNotification) {
      if (_scrollDragActive && notification.overscroll < 0) {
        // Leading-edge pull: the finger drags down while the clamped
        // scrollable sits at its top, so the content cannot scroll further and
        // every absorbed delta must move the sheet instead.
        _overscrollAccum += notification.overscroll;
        _setPull(-_overscrollAccum);
      }
    } else if (notification is ScrollUpdateNotification) {
      final pixels = notification.metrics.pixels;
      if (_scrollDragActive && pixels < 0) {
        // Bouncing physics (iOS): a downward pull at the top moves the content
        // below its edge; mirror that offset as the sheet pull.
        _overscrollAccum = pixels;
        _setPull(-pixels);
      } else if (_scrollDragActive && pixels > 0 && _pullPx > 0) {
        // The user scrolled back into the content: cancel the pull.
        _overscrollAccum = 0;
        _controller.duration = widget.springDuration;
        _animateBack();
      }
    } else if (notification is ScrollEndNotification) {
      if (_scrollDragActive) {
        _scrollDragActive = false;
        _finishDrag();
      }
    }
    return false;
  }

  /// Starts the fallback drag only after the gesture arena awards a vertical
  /// drag to the sheet. A nested scrollable can therefore win the arena and
  /// keep its own horizontal/vertical gesture completely independent.
  void _onVerticalDragStart(DragStartDetails details) {
    if (_scrollDragActive || _closing) return;
    _verticalDragActive = true;
    _dragStartY = details.localPosition.dy;
    _dragStartScrollOffset = _scrollOffset;
    _controller.stop();
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    if (!_verticalDragActive || _scrollDragActive) return;
    final netDy = details.localPosition.dy - _dragStartY;
    // Movement the primary scrollable absorbed while returning to its top
    // must not translate the sheet; only the unconsumed remainder does.
    final consumedByScroll = (_dragStartScrollOffset - _scrollOffset).clamp(
      0.0,
      double.infinity,
    );
    final effective = (netDy - consumedByScroll).clamp(0.0, _maxPull);
    _setPull(effective);
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    if (!_verticalDragActive || _scrollDragActive) return;
    _finishDrag();
  }

  void _onVerticalDragCancel() {
    if (!_verticalDragActive) return;
    _verticalDragActive = false;
    _controller.duration = widget.springDuration;
    _animateBack();
  }

  Future<void> _animateBack() async {
    try {
      await _controller.animateBack(0);
    } on TickerCanceled {
      // A new drag started while the sheet was springing back.
    }
  }

  Future<void> _finishDrag() async {
    if (_closing) {
      return;
    }
    _verticalDragActive = false;
    if (_pullPx >= widget.closeThreshold) {
      _closing = true;
      _controller.duration = widget.closeDuration;
      try {
        await _controller.animateTo(1);
      } on TickerCanceled {
        // A new drag started while the sheet was sliding away.
        _closing = false;
        return;
      }
      if (mounted) {
        final popped = await Navigator.of(context).maybePop();
        if (!popped) {
          // The route refused to pop (e.g. an unsaved-changes guard): spring
          // back instead of leaving the sheet stuck translated.
          _controller.duration = widget.springDuration;
          await _animateBack();
        }
      }
      _closing = false;
    } else {
      _controller.duration = widget.springDuration;
      await _animateBack();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder:
          (context, child) =>
              Transform.translate(offset: Offset(0, _pullPx), child: child),
      child: NotificationListener<ScrollNotification>(
        onNotification: _handleScroll,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragStart: _onVerticalDragStart,
          onVerticalDragUpdate: _onVerticalDragUpdate,
          onVerticalDragEnd: _onVerticalDragEnd,
          onVerticalDragCancel: _onVerticalDragCancel,
          child: widget.child,
        ),
      ),
    );
  }
}
