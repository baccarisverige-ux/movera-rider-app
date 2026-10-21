import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/location/geocoding_repository.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/active_ride/application/route_change_controller.dart';
import 'package:movera_rider/features/active_ride/presentation/route_change_flow.dart';
import 'package:movera_rider/features/active_ride/presentation/route_change_sheet.dart';
import 'package:movera_rider/features/destination_search/presentation/route_picker_page.dart';
import 'package:movera_rider/features/home/presentation/widgets/premium_route_location_badge.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/ride_booking/domain/route_stop.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:movera_rider/shared/widgets/early_input_capture.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Records what Change route asks the geocoder; knows no address.
class _Geo implements GeocodingRepository {
  final List<String> asked = [];

  @override
  Future<PlaceResult?> forward(String query) async {
    asked.add(query);
    return null;
  }

  @override
  Future<String?> reverse(GeoPoint point) async => null;
}

/// R4.9: Where to? / Change route (rider-u87, u88, u89, u90).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => L10n.use('en'));

  /// Opens [page] over a home screen, as Home and the ride screens do.
  Future<void> open(WidgetTester tester, Widget page) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => page)),
            child: const Text('under'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('under'));
    await tester.pumpAndSettle();
  }

  RoutePickerPage picker({
    String? pickup = 'Sveavägen 1, Stockholm',
    String initialField = 'destination',
    List<String> recent = const [],
    Future<RoutePickerMapPick?> Function({
      required bool pickup,
      required String address,
    })?
    onPickOnMap,
    required Future<Map<String, dynamic>?> Function(RoutePickerSelection)
    onFinish,
  }) => RoutePickerPage(
    pickupAddress: pickup,
    destinationAddress: '',
    stops: const [],
    stopsSupported: true,
    initialField: initialField,
    capture: EarlyInputCapture(),
    here: const GeoPoint(59.33, 18.06),
    homeAddress: null,
    workAddress: null,
    recent: recent,
    onSetFavourite: (_) async => null,
    onPickOnMap:
        onPickOnMap ?? ({required pickup, required address}) async => null,
    onFinish: onFinish,
  );

  testWidgets('rider-u87: swapping the last stop and the destination keeps '
      'their booked points, so nothing is geocoded from text', (tester) async {
    const rideId = 'u87-ride';
    final server = InProcessMockClient();
    server.rides[rideId] = {
      'id': rideId,
      'status': 'driverAssigned',
      'pickupAddress': 'Sergels torg 1',
      'pickupLat': 59.3326,
      'pickupLng': 18.0649,
      'destinationAddress': 'Dropped pin · 59.34260° N',
      'destinationLat': 59.3426,
      'destinationLng': 18.0498,
      'price': 200.0,
      'bookedPrice': 200.0,
      'bookedKm': 1.4,
      'stops': <Map<String, dynamic>>[],
      'version': 3,
    };
    final geo = _Geo();
    final ride = RideSnapshot(
      status: RideStatus.driverAssigned,
      savedAt: DateTime(2026, 10, 21),
      pickupAddress: 'Sergels torg 1',
      destinationAddress: 'Dropped pin · 59.34260° N',
      pickupLat: 59.3326,
      pickupLng: 18.0649,
      destinationLat: 59.3426,
      destinationLng: 18.0498,
      stops: const [
        RouteStop(address: 'Hötorget 1', latitude: 59.3365, longitude: 18.0586),
      ],
      rideType: 'Movera',
      price: 200,
      paymentMethod: 'Apple Pay',
      rideId: rideId,
    );
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => openRouteChange(
              context,
              ride: ride,
              entry: RouteChangeEntry.destination,
              pickupLocked: true,
              controller: RouteChangeController(
                api: ApiClient(client: server),
                geocoding: geo,
              ),
            ),
            child: const Text('ride'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('ride'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('route-picker-swap-stop')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('route-picker-done')));
    final sheet = find.byType(RouteChangeSheet);
    for (var i = 0; i < 40 && sheet.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(geo.asked, isEmpty);
    expect(sheet, findsOneWidget);
  });

  testWidgets('rider-u88: back while the next step runs does not close the '
      'picker under it', (tester) async {
    final step = Completer<Map<String, dynamic>?>();
    await open(
      tester,
      picker(
        recent: const ['Drottninggatan 50, Stockholm'],
        onFinish: (_) => step.future,
      ),
    );
    await tester.tap(find.textContaining('Drottninggatan').first);
    await tester.pump();

    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(RoutePickerPage), findsOneWidget);

    step.complete(null);
    await tester.pumpAndSettle();
    expect(find.byType(RoutePickerPage), findsOneWidget);
  });

  group('rider-u89: Choose on map gets the pickup as stored, not as shown', () {
    Future<String?> mapAddress(WidgetTester tester, String pickup) async {
      String? sent;
      await open(
        tester,
        picker(
          pickup: pickup,
          initialField: 'pickup',
          onPickOnMap: ({required pickup, required address}) async {
            sent = address;
            return null;
          },
          onFinish: (_) async => null,
        ),
      );
      await tester.tap(find.byType(PremiumRouteLocationBadge));
      await tester.pumpAndSettle();
      return sent;
    }

    testWidgets('a long geocoder address', (tester) async {
      const full = 'Sveavägen 1, 111 57 Stockholm, Sverige';
      expect(await mapAddress(tester, full), full);
    });

    testWidgets('the location-off placeholder in Swedish', (tester) async {
      L10n.use('sv');
      expect(
        await mapAddress(tester, 'Location off, set pickup'),
        'Location off, set pickup',
      );
    });
  });

  testWidgets('rider-u90: Enter never books a result of an older query', (
    tester,
  ) async {
    final sent = <String>[];
    await open(
      tester,
      picker(
        onFinish: (selection) async {
          sent.add(selection.destination);
          return null;
        },
      ),
    );
    TextField destination() => tester.widget<TextField>(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == 'Where to?',
      ),
    );
    // Suggestions come from the app's in-process backend, on a real clock.
    Future<void> until(Finder rows) async {
      for (var i = 0; i < 100 && rows.evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
    }

    final row = find.byIcon(Icons.location_on_outlined);
    await tester.enterText(find.byWidget(destination()), 'Kungsgatan');
    await until(row);
    expect(row, findsWidgets);

    // The rider types on and presses Enter before the new answer arrives.
    destination().controller!.text = 'Kungsgatan 44';
    destination().onChanged!('Kungsgatan 44');
    destination().onSubmitted!('Kungsgatan 44');
    await tester.pump();
    expect(sent, isEmpty);

    // Once the list is for what the field says, Enter takes its first row.
    await until(
      find.descendant(
        of: find.byType(ListView),
        matching: find.textContaining('Kungsgatan 44', findRichText: true),
      ),
    );
    destination().onSubmitted!('Kungsgatan 44');
    await tester.pump();
    expect(sent.single, startsWith('Kungsgatan 44'));
  });
}
