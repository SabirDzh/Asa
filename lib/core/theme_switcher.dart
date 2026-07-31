import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

class ThemeSwitcher {
  static final GlobalKey boundaryKey = GlobalKey();

  static Future<void> switchTheme({
    required BuildContext context,
    required VoidCallback onToggle,
  }) async {
    final boundary =
        boundaryKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (boundary == null) {
      onToggle();
      return;
    }

    final pixelRatio = View.of(context).devicePixelRatio;
    final captureRatio = pixelRatio > 2.0 ? 2.0 : pixelRatio;
    final overlayState = Overlay.of(context);

    // Capture the current screen state as an image.
    final image = await boundary.toImage(pixelRatio: captureRatio);

    late OverlayEntry overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) {
        return _ThemeTransitionOverlay(
          image: image,
          onComplete: () {
            overlayEntry.remove();
          },
        );
      },
    );

    overlayState.insert(overlayEntry);

    // Toggle the theme immediately under the overlay. The overlay will
    // cross-fade to the new theme.
    onToggle();
  }
}

class _ThemeTransitionOverlay extends StatefulWidget {
  final ui.Image image;
  final VoidCallback onComplete;

  const _ThemeTransitionOverlay({
    required this.image,
    required this.onComplete,
  });

  @override
  _ThemeTransitionOverlayState createState() => _ThemeTransitionOverlayState();
}

class _ThemeTransitionOverlayState extends State<_ThemeTransitionOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // Fixed 500ms duration; timeDilation globally scales it based on the
    // user's animation speed setting.
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _controller.forward().then((_) {
      widget.onComplete();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    widget.image.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: FadeTransition(
        opacity: ReverseAnimation(_controller),
        child: RawImage(
          image: widget.image,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
        ),
      ),
    );
  }
}
