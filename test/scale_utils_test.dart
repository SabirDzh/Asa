import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
