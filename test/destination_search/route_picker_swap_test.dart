import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/destination_search/presentation/route_picker_page.dart';
import 'package:movera_rider/shared/widgets/early_input_capture.dart';

/// Q1: a small swap between each two neighbouring addresses, one global
/// "reverse trip", and a re-quote after either.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  const here = GeoPoint(59.33, 18.06);

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

  testWidgets('the neighbour swap swaps those two addresses only', (
    tester,
  ) async {
    await pump(
      tester,
      stops: const ['Shop', 'Gym'],
      onFinish: (_) async => null,
    );
    expect(route(tester), ['Home', 'Shop', 'Gym', 'Work']);
    // One small swap between each two neighbours.
    for (var i = 0; i < 3; i++) {
      expect(find.byKey(ValueKey('route-picker-swap-$i')), findsOneWidget);
    }
    await tester.tap(find.byKey(const ValueKey('route-picker-swap-1')));
    await tester.pump();
    expect(route(tester), ['Home', 'Gym', 'Shop', 'Work']);
    await tester.tap(find.byKey(const ValueKey('route-picker-swap-2')));
    await tester.pump();
    expect(route(tester), ['Home', 'Gym', 'Work', 'Shop']);
  });

  testWidgets('the global button reverses the whole trip and re-quotes it', (
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
    // Home has no finish button until the route changed.
    expect(find.byKey(const ValueKey('route-picker-done')), findsNothing);
    await tester.tap(find.byTooltip('Reverse trip'));
    await tester.pump();
    expect(route(tester), ['Work', 'Shop', 'Home']);

    await tester.tap(find.byKey(const ValueKey('route-picker-done')));
    await tester.pumpAndSettle();
    expect(sent?.pickup, 'Work');
    expect(sent?.stops, ['Shop']);
    expect(sent?.destination, 'Home');
    // The GPS point travels with the old pickup; the new pickup has none
    // and is located from its address.
    expect(sent?.destinationPoint, here);
    expect(sent?.pickupPoint, isNull);
  });

  testWidgets('a locked pickup keeps its place: no swap touches it', (
    tester,
  ) async {
    await pump(
      tester,
      pickupLocked: true,
      finishLabel: 'See new price',
      onFinish: (_) async => null,
    );
    expect(find.byKey(const ValueKey('route-picker-swap-0')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('route-picker-swap-1')));
    await tester.pump();
    expect(route(tester), ['Home', 'Work', 'Shop']);
  });
}
