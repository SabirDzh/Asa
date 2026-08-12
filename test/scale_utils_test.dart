import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:asa/core/responsive_center.dart';
import 'package:asa/core/scale_utils.dart';

void main() {
  testWidgets(
    'uses the physical viewport for adaptive range inside scaled content',
    (tester) async {
      AdaptiveAppScaleRange? range;

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(300, 600)),
          child: AppScaleViewport(
            physicalSize: const Size(400, 800),
            child: Builder(
              builder: (context) {
                range = getAdaptiveScaleRange(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      expect(range, isNotNull);
      expect(range!.min, 0.8);
      expect(range!.max, 1.3);
    },
  );

  testWidgets('ResponsiveCenter keeps tablet breakpoint on a scaled viewport', (
    tester,
  ) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(500, 1000)),
        child: AppScaleViewport(
          physicalSize: const Size(700, 1400),
          child: ResponsiveCenter(
            child: Builder(
              builder:
                  (context) => SizedBox(
                    key: const ValueKey('responsive-content'),
                    width: double.infinity,
                    height: 10,
                  ),
            ),
          ),
        ),
      ),
    );

    final content = tester.getSize(
      find.byKey(const ValueKey('responsive-content')),
    );
    // Physical width 700 is in the tablet range even though the scaled
    // virtual canvas is only 500 logical pixels wide.
    expect(content.width, 552);
  });

  testWidgets('uses the current viewport without the scale marker', (
    tester,
  ) async {
    AdaptiveAppScaleRange? range;

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(300, 600)),
        child: Builder(
          builder: (context) {
            range = getAdaptiveScaleRange(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(range, isNotNull);
    expect(range!.min, 0.95);
    expect(range!.max, 1.1);
  });
}
