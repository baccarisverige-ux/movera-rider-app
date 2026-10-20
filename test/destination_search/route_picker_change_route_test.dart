import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/destination_search/presentation/route_picker_page.dart';
import 'package:movera_rider/shared/widgets/early_input_capture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<void> pump(
    WidgetTester tester, {
    required bool pickupLocked,
    bool openWithNewStop = false,
    required Future<Map<String, dynamic>?> Function(RoutePickerSelection) onFinish,
  }) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: RoutePickerPage(
          pageTitle: 'Change route',
          pickupAddress: 'Sergels torg 1',
          destinationAddress: 'Odenplan 2',
          stops: const ['Hötorget 1'],
          stopsSupported: true,
          pickupLocked: pickupLocked,
          openWithNewStop: openWithNewStop,
          initialField: 'destination',
          finishLabel: 'See new price',
          capture: EarlyInputCapture(),
          here: const GeoPoint(59.33, 18.06),
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

  testWidgets('a locked pickup is shown but cannot be edited or swapped',
      (tester) async {
    await pump(tester, pickupLocked: true, onFinish: (_) async => null);
    expect(find.text('Change route'), findsOneWidget);
    expect(find.byKey(const ValueKey('route-picker-pickup-locked')), findsOneWidget);
    final pickupField = tester.widget<TextField>(
      find.byWidgetPredicate(
        (w) => w is TextField && w.controller?.text == 'Sergels torg 1',
      ),
    );
    expect(pickupField.enabled, isFalse);
    // Q1: with a stop the only swap is last stop <-> destination, which
    // never moves the locked pickup.
    expect(find.widgetWithIcon(IconButton, Icons.swap_vert_rounded), findsNothing);
    await tester.tap(find.byKey(const ValueKey('route-picker-swap-stop')));
    await tester.pump();
    expect(pickupField.controller?.text, 'Sergels torg 1');
  });

  testWidgets('See new price sends the current route with its stops',
      (tester) async {
    RoutePickerSelection? sent;
    await pump(
      tester,
      pickupLocked: true,
      onFinish: (selection) async {
        sent = selection;
        return {'ok': true};
      },
    );
    await tester.tap(find.byKey(const ValueKey('route-picker-done')));
    await tester.pumpAndSettle();
    expect(sent?.pickup, 'Sergels torg 1');
    expect(sent?.destination, 'Odenplan 2');
    expect(sent?.stops, ['Hötorget 1']);
  });

  testWidgets('Add stop opens with a new, empty stop focused', (tester) async {
    await pump(
      tester,
      pickupLocked: false,
      openWithNewStop: true,
      onFinish: (_) async => null,
    );
    expect(find.text('Stop 2'), findsOneWidget);
    final newStop = tester.widget<TextField>(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == 'Stop 2',
      ),
    );
    expect(newStop.focusNode?.hasFocus, isTrue);
  });
}
