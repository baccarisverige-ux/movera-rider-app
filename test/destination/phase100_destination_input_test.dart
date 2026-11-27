import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/app/navigator_key.dart';
import 'package:movera_rider/core/location/geocoding_repository.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/home/presentation/home.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/saved_places/presentation/pickup_location.dart';
import 'package:movera_rider/shared/widgets/early_input_capture.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Batch 9 Phase 100 — destination input integrity (D-001), hiding stops the
/// client can't honour (U5 stopgap) and wiring the saved-place search (D-023).
void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> type(String text) async {
    for (final character in text.split('')) {
      final key = LogicalKeyboardKey(character.toLowerCase().codeUnitAt(0));
      await simulateKeyDownEvent(key, character: character);
      await simulateKeyUpEvent(key);
    }
  }

  group('D-001 early input capture', () {
    late EarlyInputCapture capture;
    late TextEditingController destination;
    late TextEditingController stop;
    late FocusNode destinationFocus;
    late FocusNode stopFocus;

    setUp(() {
      capture = EarlyInputCapture();
      destination = TextEditingController();
      stop = TextEditingController();
      destinationFocus = FocusNode();
      stopFocus = FocusNode();
    });

    tearDown(() {
      capture.stop();
      destination.dispose();
      stop.dispose();
      destinationFocus.dispose();
      stopFocus.dispose();
    });

    Future<void> pumpFields(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                TextField(controller: destination, focusNode: destinationFocus),
                TextField(controller: stop, focusNode: stopFocus),
              ],
            ),
          ),
        ),
      );
    }

    testWidgets('typing in a focused stop field never writes the destination', (
      tester,
    ) async {
      await pumpFields(tester);
      capture.start();
      capture.attach(destination, destinationFocus);
      destination.text = 'Centralen';

      stopFocus.requestFocus();
      await tester.pump();
      await type('abc');
      await simulateKeyDownEvent(LogicalKeyboardKey.backspace);
      await simulateKeyUpEvent(LogicalKeyboardKey.backspace);

      expect(destination.text, 'Centralen');
    });

    testWidgets('capture stops for good once the destination was focused', (
      tester,
    ) async {
      await pumpFields(tester);
      capture.start();
      capture.attach(destination, destinationFocus);

      destinationFocus.requestFocus();
      await tester.pump();
      expect(capture.isCapturing, isFalse);

      // Focus leaves every text field; keys must not reach the destination.
      destinationFocus.unfocus();
      await tester.pump();
      await type('xy');

      expect(destination.text, isEmpty);
      expect(capture.isCapturing, isFalse);
    });
  });

  testWidgets('Where to? opens full screen with add-stop and swap', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // Keep SecureTokenStore off the (unanswered) secure-storage channel.
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    FindingDriverController.active = null;
    AppScope.instance.ride
      ..rideId = null
      ..status = RideStatus.idle
      ..suppressRestore = false;

    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        minTextAdapt: true,
        splitScreenMode: true,
        builder: (_, __) =>
            MaterialApp(navigatorKey: moveraNavigatorKey, home: const Home()),
      ),
    );
    // Real frames, so Home can settle (the promotion ticket may seat the
    // sheet a few frames after launch).
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.text('Where to?'));
    for (
      var i = 0;
      i < 40 && find.byType(TextField).evaluate().length < 2;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(milliseconds: 450));

    // Pickup + destination, a "+" to add a stop and a swap button. Stops are
    // shown at the owner's request (not yet sent to the quote — LATER_JOB B1).
    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.byTooltip('Add stop'), findsOneWidget);
    expect(find.byTooltip('Swap pickup and destination'), findsOneWidget);
    expect(find.text('Next'), findsNothing);
    await tester.tap(find.byTooltip('Add stop'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(TextField), findsNWidgets(3));

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    debugDefaultTargetPlatformOverride = null;
  });

  group('D-023 saved-place search', () {
    Future<void> pumpSearch(
      WidgetTester tester, {
      required Future<PlaceResult?> Function(String) geocode,
      required void Function(String?) onResult,
    }) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          minTextAdapt: true,
          splitScreenMode: true,
          builder: (_, __) => MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    onResult(
                      await Navigator.push<String>(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              RiderSearchPickupLocation(geocode: geocode),
                        ),
                      ),
                    );
                  },
                  child: const Text('Open search'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open search'));
      await tester.pumpAndSettle();
    }

    testWidgets('submitting typed text geocodes it and returns the place', (
      tester,
    ) async {
      final queries = <String>[];
      String? result;
      await pumpSearch(
        tester,
        geocode: (query) async {
          queries.add(query);
          return const PlaceResult(
            address: 'Drottninggatan 10, Stockholm',
            point: GeoPoint(59.33, 18.06),
          );
        },
        onResult: (value) => result = value,
      );

      await tester.enterText(
        find.byType(TextField).first,
        ' drottning 10 ',
      );
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(queries, ['drottning 10']);
      expect(result, 'Drottninggatan 10, Stockholm');
      expect(find.byType(RiderSearchPickupLocation), findsNothing);
    });

    testWidgets('an address that cannot be found stays put with an error', (
      tester,
    ) async {
      String? result = 'untouched';
      await pumpSearch(
        tester,
        geocode: (_) async => null,
        onResult: (value) => result = value,
      );

      await tester.enterText(find.byType(TextField).first, 'nowhere');
      await tester.tap(find.byKey(const ValueKey('saved-place-search')));
      await tester.pumpAndSettle();

      expect(result, 'untouched');
      expect(find.byType(RiderSearchPickupLocation), findsOneWidget);
      expect(
        find.byKey(const ValueKey('saved-place-search-error')),
        findsOneWidget,
      );
    });
  });
}
