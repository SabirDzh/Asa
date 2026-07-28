import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

class ThemeSwitcher {
  static final GlobalKey boundaryKey = GlobalKey();

  static Future<void> switchTheme({
    required BuildContext context,
    required Offset center,
    required VoidCallback onToggle,
    required double animationSpeed,
  }) async {
    final boundary = boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) {
      onToggle();
      return;
    }

    final pixelRatio = View.of(context).devicePixelRatio;
    final captureRatio = pixelRatio > 2.0 ? 2.0 : pixelRatio;
    final overlayState = Overlay.of(context);

    // Capture the current screen state as an image
    final image = await boundary.toImage(pixelRatio: captureRatio);

    late OverlayEntry overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) {
        return _ThemeTransitionOverlay(
          image: image,
          center: center,
          animationSpeed: animationSpeed,
          onComplete: () {
            overlayEntry.remove();
          },
        );
      },
    );

    overlayState.insert(overlayEntry);

    // Toggle the theme immediately under the overlay
    onToggle();
  }
}

class _ThemeTransitionOverlay extends StatefulWidget {
  final ui.Image image;
  final Offset center;
  final double animationSpeed;
  final VoidCallback onComplete;

  const _ThemeTransitionOverlay({
    required this.image,
    required this.center,
    required this.animationSpeed,
    required this.onComplete,
  });

  @override
  _ThemeTransitionOverlayState createState() => _ThemeTransitionOverlayState();
}

class _ThemeTransitionOverlayState extends State<_ThemeTransitionOverlay> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // Use a fixed 500ms duration. timeDilation globally scales it based on user setting.
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return ClipPath(
            clipper: _HoleClipper(center: widget.center, progress: _controller.value),
            child: child!,
          );
        },
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

class _HoleClipper extends CustomClipper<Path> {
  final Offset center;
  final double progress;

  _HoleClipper({required this.center, required this.progress});

  @override
  Path getClip(Size size) {
    final Path path = Path();
    path.addRect(Rect.fromLTWH(0, 0, size.width, size.height));

    final double maxRadius = _calcMaxRadius(size, center);
    // As progress goes 0 -> 1, the hole radius grows 0 -> maxRadius
    final double currentRadius = maxRadius * progress;

    final Path hole = Path();
    hole.addOval(Rect.fromCircle(center: center, radius: currentRadius));

    // Subtract the hole from the full rect, meaning the old UI will be clipped OUT 
    // inside the expanding circle, revealing the new UI underneath!
    return Path.combine(PathOperation.difference, path, hole);
  }

  double _calcMaxRadius(Size size, Offset center) {
    final w = size.width;
    final h = size.height;
    
    // Distances from center to all 4 corners
    final d1 = center.distance; // Top-left
    final d2 = (Offset(w, 0) - center).distance; // Top-right
    final d3 = (Offset(0, h) - center).distance; // Bottom-left
    final d4 = (Offset(w, h) - center).distance; // Bottom-right
    
    return [d1, d2, d3, d4].reduce((a, b) => a > b ? a : b);
  }

  @override
  bool shouldReclip(_HoleClipper oldClipper) => progress != oldClipper.progress;
}
