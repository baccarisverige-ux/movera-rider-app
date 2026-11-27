import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/destination_search/presentation/route_picker_page.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/saved_places/presentation/pickup_location.dart';
import 'package:movera_rider/features/scheduled_rides/presentation/schedule_ride.dart';
import 'package:movera_rider/shared/widgets/early_input_capture.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Schedule ride and Save address show the same autocomplete suggestions
/// as "Where to?" while typing (in-process fake autocomplete), and picking
/// one fills the address.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });
  void size(WidgetTester t) {
    t.view.physicalSize = const Size(390 * 3, 844 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
  }

  int suggestionRows() =>
      find.byIcon(Icons.location_on_outlined).evaluate().length;

  testWidgets('CONTROL: Where to? (RoutePickerPage) shows suggestions', (
    t,
  ) async {
    size(t);
    await t.pumpWidget(
      MaterialApp(
        home: RoutePickerPage(
          pageTitle: 'Where to?',
          pickupAddress: 'Sergels torg 1',
          destinationAddress: '',
          stops: const [],
          stopsSupported: true,
          pickupLocked: false,
          initialField: 'destination',
          finishLabel: 'Done',
          capture: EarlyInputCapture(),
          here: const GeoPoint(59.33, 18.06),
          homeAddress: null,
          workAddress: null,
          recent: const [],
          onSetFavourite: (_) async => null,
          onPickOnMap: ({required pickup, required address}) async => null,
          onFinish: (_) async => null,
        ),
      ),
    );
    await t.pumpAndSettle();
    final before = suggestionRows();
    await t.enterText(
      find
          .byWidgetPredicate(
            (w) => w is TextField && w.focusNode?.hasFocus == true,
          )
          .first,
      'Friend',
    );
    await t.pump(const Duration(seconds: 1));
    await t.pumpAndSettle();
    expect(suggestionRows(), greaterThan(before));
  });

  testWidgets(
    'Schedule ride dropoff field shows suggestions; a pick fills it',
    (t) async {
      size(t);
      await t.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (_, _) => const MaterialApp(home: ScheduleRide()),
        ),
      );
      await t.pumpAndSettle();
      final before = suggestionRows();
      await t.enterText(find.byType(TextField).at(1), 'Friend');
      await t.pump(const Duration(seconds: 1));
      await t.pumpAndSettle();
      expect(
        suggestionRows(),
        greaterThan(before),
        reason: 'no suggestion list under the schedule address field',
      );
      await t.tap(find.byKey(const ValueKey('address-suggestion-0')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('address-suggestions')), findsNothing);
      final field = t.widget<TextField>(find.byType(TextField).at(1));
      expect(field.controller!.text, startsWith('Friend'));
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 10));
    },
  );

  testWidgets(
    'Save address shows suggestions while typing; a pick returns it',
    (t) async {
      size(t);
      Object? returned;
      var geocodes = 0;
      await t.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (_, _) => MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  returned = await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => RiderSearchPickupLocation(
                        geocode: (q) async {
                          geocodes++;
                          return null;
                        },
                      ),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      expect(suggestionRows(), 0);
      await t.enterText(find.byType(TextField), 'Odenplan');
      await t.pump(const Duration(seconds: 1));
      await t.pumpAndSettle();
      expect(
        suggestionRows(),
        greaterThan(0),
        reason: 'no suggestions while typing',
      );
      await t.tap(find.byKey(const ValueKey('address-suggestion-0')));
      await t.pumpAndSettle();
      expect(returned, isA<String>());
      expect(returned as String, contains('Odenplan'));
      expect(geocodes, 0, reason: 'a picked suggestion needs no geocode');
    },
  );

  final booked = Reservation.tryParse({
    'reservationId': 'rsv_1',
    'createdAt': '2026-10-20T10:00:00Z',
    'scheduledPickupAt': '2026-12-22T08:00:00Z',
    'pickup': {'label': 'Klockarvägen 37', 'lat': 59.3, 'lng': 18.0},
    'destination': {'label': 'Arlanda Airport', 'lat': 59.6, 'lng': 17.9},
  })!;
  for (final (field, name) in [(0, 'pickup'), (1, 'dropoff')]) {
    testWidgets('Changing a booked ride: $name field shows suggestions', (
      t,
    ) async {
      size(t);
      await t.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (_, _) => MaterialApp(home: ScheduleRide(editing: booked)),
        ),
      );
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField).at(field), 'Friend');
      await t.pump(const Duration(seconds: 1));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('address-suggestions')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('address-suggestion-0')),
        findsOneWidget,
      );
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 10));
    });
  }
}
