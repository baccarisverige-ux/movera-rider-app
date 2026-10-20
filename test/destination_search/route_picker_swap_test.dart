import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/destination_search/presentation/route_picker_page.dart';
import 'package:movera_rider/shared/widgets/early_input_capture.dart';

/// Q1 (owner, revised): one swap. With stops it swaps the last stop and
/// the destination only; with no stops pickup and drop-off. A swap
/// re-quotes ("See prices").
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  const here = GeoPoint(59.33, 18.06);
  final stopSwap = find.byKey(const ValueKey('route-picker-swap-stop'));
  final pickupSwap = find.byTooltip('Swap pickup and destination');

  Future<void> pump(
    WidgetTester tester, {
    List<String> stops = const ['Shop'],
    bool pickupLocked = false,
    String? finishLabel,
    required Future<Map<String, dynamic>?> Function(RoutePickerSelection)
    onFinish,
  }) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: RoutePickerPage(
          pickupAddress: 'Home',
          destinationAddress: 'Work',
          stops: stops,
          stopsSupported: true,
          pickupLocked: pickupLocked,
          initialField: 'destination',
          finishLabel: finishLabel,
          capture: EarlyInputCapture(),
          here: here,
          homeAddress: null,
          workAddress: null,
          recent: const [],
          onSetFavourite: (_) async => null,
          onPickOnMap: ({required pickup, required address}) async => null,
          onFinish: onFinish,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  List<String> route(WidgetTester tester) => [
    for (final field in tester.widgetList<TextField>(find.byType(TextField)))
      field.controller!.text,
  ];

  testWidgets('with stops there is one swap: last stop and destination', (
    tester,
  ) async {
    await pump(
      tester,
      stops: const ['Shop', 'Gym'],
      onFinish: (_) async => null,
    );
    expect(route(tester), ['Home', 'Shop', 'Gym', 'Work']);
    expect(stopSwap, findsOneWidget);
    expect(pickupSwap, findsNothing);
    expect(find.byIcon(Icons.swap_vert_rounded), findsOneWidget);
    await tester.tap(stopSwap);
    await tester.pump();
    expect(route(tester), ['Home', 'Shop', 'Work', 'Gym']);
  });

  testWidgets('the stop swap re-quotes and never moves the pickup', (
    tester,
  ) async {
    RoutePickerSelection? sent;
    await pump(
      tester,
      onFinish: (selection) async {
        sent = selection;
        return null;
      },
    );
    expect(find.byKey(const ValueKey('route-picker-done')), findsNothing);
    await tester.tap(stopSwap);
    await tester.pump();
    expect(route(tester), ['Home', 'Work', 'Shop']);
    await tester.tap(find.byKey(const ValueKey('route-picker-done')));
    await tester.pumpAndSettle();
    expect(sent?.pickup, 'Home');
    expect(sent?.pickupPoint, here);
    expect(sent?.stops, ['Work']);
    expect(sent?.destination, 'Shop');
    // The old stop has no point; it is located from its address.
    expect(sent?.destinationPoint, isNull);
  });

  testWidgets('without stops the swap is pickup and drop-off, re-quoted', (
    tester,
  ) async {
    RoutePickerSelection? sent;
    await pump(
      tester,
      stops: const [],
      onFinish: (selection) async {
        sent = selection;
        return null;
      },
    );
    expect(stopSwap, findsNothing);
    await tester.tap(pickupSwap);
    await tester.pump();
    expect(route(tester), ['Work', 'Home']);
    await tester.tap(find.byKey(const ValueKey('route-picker-done')));
    await tester.pumpAndSettle();
    expect(sent?.pickup, 'Work');
    expect(sent?.destination, 'Home');
    expect(sent?.destinationPoint, here);
  });

  testWidgets('a locked pickup without stops cannot be swapped', (
    tester,
  ) async {
    await pump(
      tester,
      stops: const [],
      pickupLocked: true,
      finishLabel: 'See new price',
      onFinish: (_) async => null,
    );
    final swap = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.swap_vert_rounded),
    );
    expect(swap.onPressed, isNull);
  });

  testWidgets('a locked pickup still lets the last stop and destination swap',
      (tester) async {
    await pump(
      tester,
      pickupLocked: true,
      finishLabel: 'See new price',
      onFinish: (_) async => null,
    );
    await tester.tap(stopSwap);
    await tester.pump();
    expect(route(tester), ['Home', 'Work', 'Shop']);
  });
}
