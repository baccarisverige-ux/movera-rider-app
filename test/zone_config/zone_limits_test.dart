import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/config/rider_app_config.dart';
import 'package:movera_rider/core/config/trip_zone_config.dart';
import 'package:movera_rider/core/config/zone_clock.dart';
import 'package:movera_rider/core/location/geocoding_repository.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/active_ride/application/route_change_controller.dart';
import 'package:movera_rider/features/destination_search/presentation/route_picker_page.dart';
import 'package:movera_rider/features/promotions/application/rider_promotion_controller.dart';
import 'package:movera_rider/features/promotions/presentation/promotion_details_sheet.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/scheduled_rides/application/stockholm_schedule.dart';
import 'package:movera_rider/shared/widgets/early_input_capture.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'zone_config_fakes.dart';

class _Geo implements GeocodingRepository {
  _Geo(this.known);
  final Map<String, GeoPoint> known;

  @override
  Future<PlaceResult?> forward(String query) async {
    final point = known[query];
    return point == null ? null : PlaceResult(address: query, point: point);
  }

  @override
  Future<String?> reverse(GeoPoint point) async => null;
}

/// The per-zone limits Admin sets (contract v0.4.0 §6): max stops (Q39),
/// how far the pickup moves after accept (Q40), the promo cap (Q10) and
/// the zone's time zone (Q9).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  late RiderConfigRepository saved;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    saved = AppScope.instance.riderConfig;
  });
  tearDown(() => AppScope.instance.riderConfig = saved);

  group('max stops (Q39)', () {
    Future<void> pumpPicker(WidgetTester tester) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: RoutePickerPage(
            pageTitle: 'Plan your ride',
            pickupAddress: 'Sergels torg 1',
            destinationAddress: 'Odenplan 2',
            stops: const ['Hötorget 1'],
            stopsSupported: true,
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
      await tester.pumpAndSettle();
    }

    IconButton addStop(WidgetTester tester) => tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.add_rounded).first,
    );

    testWidgets('the zone allows one stop: Add stop is off with one', (
      tester,
    ) async {
      AppScope.instance.riderConfig = EditedZoneConfigs({
        'Z001': {
          'booking': {'maxStops': 1},
        },
      });
      await pumpPicker(tester);
      expect(find.byTooltip('Add stop'), findsOneWidget);
      expect(addStop(tester).onPressed, isNull);
    });

    testWidgets('the zone allows three: another stop can be added', (
      tester,
    ) async {
      AppScope.instance.riderConfig = EditedZoneConfigs({
        'Z001': {
          'booking': {'maxStops': 3},
        },
      });
      await pumpPicker(tester);
      expect(addStop(tester).onPressed, isNotNull);
      await tester.tap(find.byTooltip('Add stop'));
      await tester.pumpAndSettle();
      expect(find.text('Stop 2'), findsOneWidget);
    });
  });

  group('pickup move after accept (Q40)', () {
    const pickup = GeoPoint(59.3326, 18.0649);
    const drop = GeoPoint(59.3426, 18.0498);
    // About 300 m north of the pickup.
    const near = GeoPoint(59.3353, 18.0649);

    RideSnapshot ride() => RideSnapshot(
      status: RideStatus.driverArriving,
      savedAt: DateTime(2026, 10, 20),
      pickupAddress: 'Sergels torg 1',
      destinationAddress: 'Odenplan 2',
      pickupLat: pickup.latitude,
      pickupLng: pickup.longitude,
      destinationLat: drop.latitude,
      destinationLng: drop.longitude,
      rideType: 'Movera',
      price: 200,
      paymentMethod: 'Apple Pay',
      rideId: 'ride-move-zone',
    );

    InProcessMockClient backend(RiderAppConfig config) {
      final mock = InProcessMockClient()..riderConfig = config;
      mock.rides['ride-move-zone'] = {
        'id': 'ride-move-zone',
        'status': 'driverArriving',
        'pickupAddress': 'Sergels torg 1',
        'pickupLat': pickup.latitude,
        'pickupLng': pickup.longitude,
        'destinationAddress': 'Odenplan 2',
        'destinationLat': drop.latitude,
        'destinationLng': drop.longitude,
        'price': 200.0,
        'bookedPrice': 200.0,
        'bookedKm': 1.4,
        'stops': <Map<String, dynamic>>[],
        'version': 3,
      };
      return mock;
    }

    test('a zone limit of 200 m refuses a 300 m move, naming 200 m', () async {
      final config = await EditedZoneConfigs({
        'Z001': {
          'booking': {'maxPickupMoveMeters': 200},
        },
      }).forZone('Z001');
      expect(config.maxPickupMoveMeters, 200);
      final changes = RouteChangeController(
        api: ApiClient(client: backend(config)),
        geocoding: _Geo({'Near corner': near}),
      );
      await expectLater(
        changes.preview(
          ride: ride(),
          pickupAddress: 'Near corner',
          destinationAddress: 'Odenplan 2',
          maxPickupMoveMeters: config.maxPickupMoveMeters,
        ),
        throwsA(
          isA<RouteChangeException>()
              .having((e) => e.failure, 'failure', RouteChangeFailure.pickupTooFar)
              .having((e) => e.message, 'message', contains('up to 200 m')),
        ),
      );
    });

    test('the demo server applies the zone limit too', () async {
      final config = await EditedZoneConfigs({
        'Z001': {
          'booking': {'maxPickupMoveMeters': 200},
        },
      }).forZone('Z001');
      final api = ApiClient(client: backend(config));
      await expectLater(
        api.patch(
          '/api/v1/rides/ride-move-zone',
          body: {
            'routeChange': true,
            'pickupAddress': 'Near corner',
            'pickupLat': near.latitude,
            'pickupLng': near.longitude,
            'destinationAddress': 'Odenplan 2',
            'destinationLat': drop.latitude,
            'destinationLng': drop.longitude,
            'stops': const <Object>[],
          },
        ),
        throwsA(
          isA<ApiError>().having((e) => e.detail, 'detail', 'pickup_too_far'),
        ),
      );
    });
  });

  group('promo cap (Q10)', () {
    const promotionJson = {
      'id': 'p1',
      'title': '30% off your next 5 rides',
      'percentOff': 30,
      'ridesLeft': 4,
      'ridesTotal': 5,
      'endsAt': '2026-11-30T23:59:00',
      'maxDiscountMinor': 5000,
      'rideTypes': ['comfort'],
      'rules': <String>[],
    };

    Future<void> openSheet(WidgetTester tester, String currency) async {
      tester.view.physicalSize = const Size(390, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => PromotionDetailsSheet.open(
                  context,
                  RiderPromotion.fromJson(promotionJson)!,
                  categories: const [PromotionCategory(id: 'comfort', name: 'Comfort')],
                  currency: currency,
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
    }

    testWidgets('the sheet shows the zone config cap in euros', (tester) async {
      AppScope.instance.riderConfig = EditedZoneConfigs({
        'FR-PC': {'promoCap': wireMoney(500, 'EUR')},
      });
      await openSheet(tester, 'EUR');
      expect(find.text('Max 5 € off per ride'), findsOneWidget);
    });

    testWidgets('no cap in the config: no cap line', (tester) async {
      AppScope.instance.riderConfig = EditedZoneConfigs();
      await openSheet(tester, 'TND');
      expect(find.text('30% off your next 5 rides'), findsOneWidget);
      expect(find.textContaining('off per ride'), findsNothing);
    });
  });

  group('time zone from the config (Q9)', () {
    test('the zone config names the time zone; DST rules stay', () async {
      AppScope.instance.riderConfig = EditedZoneConfigs({
        'FR-PC': {'timeZone': 'Europe/Lisbon'},
      });
      final zone = await AppScope.instance.riderConfig.timeZoneAt(48.86, 2.34);
      expect(zone, 'Europe/Lisbon');
      // Lisbon: UTC+0 in winter, +1 in summer (EU rule).
      expect(ZoneClock.offsetAt(zone, DateTime.utc(2026, 1, 15)), Duration.zero);
      expect(
        ZoneClock.offsetAt(zone, DateTime.utc(2026, 7, 15)),
        const Duration(hours: 1),
      );
      // The change happens at 01:00 UTC on the last Sunday of October.
      expect(
        ZoneClock.offsetAt(zone, DateTime.utc(2026, 10, 25, 0, 59)),
        const Duration(hours: 1),
      );
      expect(
        ZoneClock.offsetAt(zone, DateTime.utc(2026, 10, 25, 1)),
        Duration.zero,
      );
    });

    test('a pickup schedule follows the config time zone', () async {
      final config = await EditedZoneConfigs({
        'FR-PC': {'timeZone': 'Europe/Helsinki'},
      }).forZone('FR-PC');
      final schedule = PickupSchedule.at(48.86, 2.34, config: config);
      expect(schedule.timeZone, 'Europe/Helsinki');
      // 10:00 UTC in January is 12:00 in Helsinki (EET).
      expect(
        schedule.zoneNow(DateTime.utc(2026, 1, 15, 10)),
        DateTime.utc(2026, 1, 15, 12),
      );
      // Without a config, the seed's: Paris.
      expect(PickupSchedule.at(48.86, 2.34).timeZone, 'Europe/Paris');
      // Tunis keeps UTC+1 all year.
      expect(
        PickupSchedule.at(36.8, 10.18).zoneNow(DateTime.utc(2026, 7, 1, 10)),
        DateTime.utc(2026, 7, 1, 11),
      );
    });
  });
}
