import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/home/presentation/widgets/plan_ride_address_box.dart';

/// Batch 10 Phase 112 — the add-stop button sits inside the bordered address
/// box, pinned to its top, circular, with a red plus. Home keeps it hidden
/// (`_stopsSupported` is `static const false`), so this pumps the extracted
/// widget directly. Behavioural only (no source reads).
void main() {
  const red = Color(0xFFE31E37);

  Widget row(String label, {Key? key, bool removable = false}) => Row(
    children: [
      const SizedBox(width: 27, height: 27),
      const SizedBox(width: 8),
      Expanded(
        child: TextField(
          key: key,
          decoration: InputDecoration(labelText: label, isDense: true),
        ),
      ),
      if (removable)
        IconButton(
          onPressed: () {},
          icon: const Icon(Icons.close_rounded),
          tooltip: 'Remove stop',
        ),
    ],
  );

  List<Widget> rows(int stops) => [
    row('Pickup', key: const Key('pickup')),
    const Divider(height: 1),
    for (var i = 0; i < stops; i++) ...[
      row('Stop ${i + 1}', key: Key('stop$i'), removable: true),
      const Divider(height: 1),
    ],
    row('Final destination', key: const Key('destination')),
  ];

  Future<int> pump(
    WidgetTester tester, {
    double width = 390,
    int stops = 0,
    bool show = true,
  }) async {
    var taps = 0;
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        minTextAdapt: true,
        splitScreenMode: true,
        builder: (_, __) => MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(14),
              child: StatefulBuilder(
                builder: (context, setState) => Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: PlanRideAddressBox(
                            key: const Key('box'),
                            routeRows: rows(stops),
                            showAddStop: show,
                            stopCount: stops,
                            onAddStop: () => setState(() {
                              taps += 1;
                              stops += 1;
                            }),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return taps;
  }

  final button = find.byKey(PlanRideAddressBox.addStopKey);
  final box = find.byKey(const Key('box'));

  Color iconColor(WidgetTester tester) => tester
      .widget<Icon>(
        find.descendant(of: button, matching: find.byIcon(Icons.add_rounded)),
      )
      .color!;

  testWidgets(
    'button renders inside the bordered box, pinned to its top-right',
    (tester) async {
      await pump(tester);
      expect(button, findsOneWidget);
      final b = tester.getRect(button);
      final r = tester.getRect(box);
      expect(
        r.contains(b.topLeft) && r.contains(b.bottomRight),
        isTrue,
        reason: 'button $b must sit inside box $r',
      );
      expect(b.top - r.top, lessThan(16), reason: 'pinned to the top');
      expect(r.right - b.right, lessThan(16), reason: 'at the right edge');
      // Top half of the box, level with the pickup row.
      final pickup = tester.getRect(find.byKey(const Key('pickup')));
      expect(b.center.dy, lessThan(pickup.bottom + 8));
    },
  );

  testWidgets('circular, with a red plus (AppColor.red #E31E37)', (
    tester,
  ) async {
    await pump(tester);
    final material = tester.widget<Material>(button);
    expect(material.shape, isA<CircleBorder>());
    final size = tester.getSize(button);
    expect(size.width, closeTo(size.height, 0.01));
    expect(iconColor(tester), red);
    expect(PlanRideAddressBox.addStopColor, red);
  });

  testWidgets(
    'tap adds a stop via the same callback; disabled and dimmed at 3',
    (tester) async {
      await pump(tester, stops: 2);
      expect(find.byKey(const Key('stop1')), findsOneWidget);
      await tester.tap(button);
      await tester.pump();
      expect(find.byKey(const Key('stop2')), findsOneWidget);

      // Now at 3 stops: disabled, not red, tapping does nothing.
      final ink = tester.widget<InkWell>(
        find.descendant(of: button, matching: find.byType(InkWell)),
      );
      expect(ink.onTap, isNull);
      expect(iconColor(tester), PlanRideAddressBox.addStopDisabledColor);
      expect(iconColor(tester), isNot(red));
      await tester.tap(button, warnIfMissed: false);
      await tester.pump();
      expect(find.byKey(const Key('stop3')), findsNothing);
    },
  );

  for (final width in const [320.0, 390.0]) {
    for (final stops in const [0, 3]) {
      testWidgets('no overlap with any field or clear button at '
          '${width.toInt()} px, $stops stops', (tester) async {
        await pump(tester, width: width, stops: stops);
        expect(tester.takeException(), isNull);
        final b = tester.getRect(button);
        final fields = find.byType(TextField);
        expect(fields, findsNWidgets(2 + stops));
        for (final element in fields.evaluate()) {
          final f = tester.getRect(find.byWidget(element.widget));
          expect(f.overlaps(b), isFalse, reason: 'field $f overlaps $b');
          expect(f.width, greaterThan(120), reason: 'field stays usable');
        }
        for (final element in find.byTooltip('Remove stop').evaluate()) {
          final c = tester.getRect(find.byWidget(element.widget));
          expect(c.overlaps(b), isFalse, reason: 'clear $c overlaps $b');
        }
      });
    }
  }

  testWidgets('hidden (Home today): no button, rows use the full width', (
    tester,
  ) async {
    await pump(tester, show: false);
    expect(button, findsNothing);
    final r = tester.getRect(box);
    final dest = tester.getRect(find.byKey(const Key('destination')));
    // Only the box's own horizontal padding remains on the right.
    expect(r.right - dest.right, lessThan(16));
  });
}
