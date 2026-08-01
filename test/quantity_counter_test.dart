import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:asa/features/tasks/widgets/quantity_counter.dart';

void main() {
  testWidgets('increments and decrements within the 0..target range', (
    tester,
  ) async {
    var value = 1.0;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            return SizedBox(
              width: 360,
              child: QuantityCounter(
                currentValue: value,
                targetValue: 2,
                unit: 'шт',
                textColor: Colors.black,
                decreaseLabel: 'Decrease',
                increaseLabel: 'Increase',
                onAdjust: (delta) {
                  setState(() {
                    value = (value + delta).clamp(0.0, 2.0).toDouble();
                  });
                },
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('quantity-increment')));
    await tester.pump();
    expect(find.text('2 / 2 шт'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('quantity-increment')));
    await tester.pump();
    expect(find.text('2 / 2 шт'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('quantity-decrement')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('quantity-decrement')));
    await tester.pump();
    expect(find.text('0 / 2 шт'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('quantity-decrement')));
    await tester.pump();
    expect(find.text('0 / 2 шт'), findsOneWidget);
  });

  testWidgets('repeats while holding and stops after release', (tester) async {
    var value = 0.0;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            return SizedBox(
              width: 360,
              child: QuantityCounter(
                currentValue: value,
                targetValue: 100,
                unit: 'раз',
                textColor: Colors.black,
                decreaseLabel: 'Decrease',
                increaseLabel: 'Increase',
                onAdjust: (delta) {
                  setState(() {
                    value = (value + delta).clamp(0.0, 100.0).toDouble();
                  });
                },
              ),
            );
          },
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('quantity-increment'))),
    );
    await tester.pump(const Duration(milliseconds: 1000));
    await gesture.up();
    await tester.pump();

    expect(value, greaterThan(1));
    final valueAfterRelease = value;
    await tester.pump(const Duration(milliseconds: 500));
    expect(value, valueAfterRelease);
  });
}
