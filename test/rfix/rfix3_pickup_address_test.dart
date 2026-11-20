import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/feature_flags/feature_flags.dart';
import 'package:movera_rider/features/booking/application/booking_controller.dart';
import 'package:movera_rider/features/booking/application/booking_coordinator.dart';
import 'package:movera_rider/features/pickup/application/pickup_address.dart';
import 'package:movera_rider/features/pickup/presentation/set_pickup_page.dart';
import 'package:movera_rider/features/ride_booking/data/api_quote_repository.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_notes.dart';
import 'package:movera_rider/features/ride_booking/domain/route_stop.dart';
import 'package:movera_rider/features/ride_selection/application/ride_catalog_controller.dart';
import 'package:movera_rider/features/ride_selection/application/ride_selection_controller.dart';
import 'package:movera_rider/features/ride_selection/data/ride_catalog_cache.dart';
import 'package:movera_rider/features/ride_selection/presentation/select_ride.dart';
import 'package:movera_rider/shared/widgets/custom_google_map.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _origin = LatLng(59.3293, 18.0686);
const _moved = LatLng(59.3326, 18.0649);

final _rawCoordinates = RegExp(
  r'^\s*-?\d{1,3}(\.\d+)?\s*,\s*-?\d{1,3}(\.\d+)?\s*$',
);

/// A stand-in for movera-server's `POST /quotes`: it keeps the pickup of
/// each quote exactly as asked and echoes it, as the server does (the trip
/// then gets the QUOTE's pickup, src/trips/service.ts `pickup:
/// JSON.stringify(quote.pickup)`), so the address in the quote request is
/// the address the driver's offer card and History show.
class _Server {
  final List<Map<String, dynamic>> quoteBodies = [];
  int _n = 0;

  /// From now on every price request fails (the server is down).
  bool down = false;

  http.Client get client => MockClient((request) async {
    if (request.method == 'POST' && request.url.path == '/api/v1/quotes') {
      if (down) {
        return _json({'code': 'internal', 'message': 'down'}, 500);
      }
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      quoteBodies.add(body);
      return _json({
        'quotes': [
          for (final category in const ['economy', 'comfort', 'xl'])
            {
              'quoteId': 'qte_${++_n}',
              'categoryId': category,
              'total': {'amountMinor': 17600, 'currency': 'SEK'},
              'fareLines': <Object>[],
              'expiresAt': DateTime.now()
                  .toUtc()
                  .add(const Duration(minutes: 5))
                  .toIso8601String(),
              'pickup': body['pickup'],
              'dropoff': body['dropoff'],
              'stops': body['stops'],
              'pickupAt': null,
            },
        ],
      });
    }
    return _json({'code': 'not_found', 'message': 'no such route'}, 404);
  });

  static http.Response _json(Map<String, Object?> body, [int status = 200]) =>
      http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json'},
      );

  List<String?> get pickupAddresses => [
    for (final body in quoteBodies)
      (body['pickup'] as Map)['address'] as String?,
  ];
}

/// Keeps what Select Ride books: the pickup address, and the `POST /trips`
/// body the app would send for the booked quote.
class _CaptureBooking extends BookingController {
  final List<({String address, Map<String, dynamic> trip})> bookings = [];

  @override
  Future<String> submitFinding({
    required String pickupAddress,
    required String destinationAddress,
    required double pickupLat,
    required double pickupLng,
    required double destinationLat,
    required double destinationLng,
    required String rideType,
    required double price,
    required String paymentMethod,
    String? quoteId,
    String? quoteSignedPayload,
    DateTime? quoteExpiresAt,
    int? quoteTotalMinor,
    String quoteCurrency = 'SEK',
    String? rideTypeLabel,
    String? paymentMethodLabel,
    RideNotes notes = RideNotes.empty,
    List<RouteStop> stops = const <RouteStop>[],
    bool useWalletFirst = false,
    int walletAmountMinor = 0,
  }) async {
    bookings.add((
      address: pickupAddress,
      trip: BookingCoordinator.contractTripBody(
        quoteId: quoteId!,
        categoryId: rideType,
        paymentMethod: 'cash',
        pickupLat: pickupLat,
        pickupLng: pickupLng,
        destinationLat: destinationLat,
        destinationLng: destinationLng,
        pickupAddress: pickupAddress,
        destinationAddress: destinationAddress,
      ),
    ));
    throw StateError('stop here');
  }
}

/// R3 (owner 2026-11-20, "Yes, all 7 as drafts"): after "Min position" or
/// any pin move on Set pickup, the ride was booked with the pin's price
/// quote, whose pickup address was the raw coordinates ("59.332600,
/// 18.064900"). The driver's offer card and History showed them.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  const staging = AppEnv(
    flavor: AppFlavor.staging,
    apiBaseUrl: 'https://api.example.test',
  );

  Future<_CaptureBooking> pumpSelectRide(
    WidgetTester tester,
    _Server server,
  ) async {
    final api = ApiClient(client: server.client, env: staging);
    final selection = RideSelectionController(
      catalog: RideCatalogController(api: api, cache: MemoryRideCatalogCache()),
      quotes: ApiQuoteRepository(api: api),
      flags: FeatureFlags(),
    );
    addTearDown(selection.dispose);
    final booking = _CaptureBooking();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: SelectRide(
          pickupAddress: 'Drottninggatan 1, Stockholm',
          destinationAddress: 'Solna Centrum, Solna torg',
          pickupPosition: _origin,
          destinationPosition: const LatLng(59.3600, 18.0000),
          selection: selection,
          booking: booking,
        ),
      ),
    );
    await settle(tester);
    return booking;
  }

  Future<void> movePin(WidgetTester tester) async {
    expect(find.byType(SetPickupPage), findsOneWidget);
    final map = tester.widget<CustomGoogleMap>(
      find.byKey(const ValueKey('set-pickup-map')),
    );
    map.onCameraMoveStarted!();
    map.onCameraMove!(const CameraPosition(target: _moved, zoom: 16));
    map.onCameraIdle!();
    await settle(tester, 20);
  }

  Future<void> confirm(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('set-pickup-confirm')));
    await settle(tester, 60);
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
  }

  testWidgets(
    'a moved pickup is booked under the address the rider confirmed, and no '
    'price request ever names the pickup by bare coordinates',
    (tester) async {
      final server = _Server();
      final booking = await pumpSelectRide(tester, server);
      await tester.tap(find.text('Select Movera'));
      await settle(tester, 30);
      await movePin(tester);
      await confirm(tester);

      expect(booking.bookings, hasLength(1));
      final booked = booking.bookings.single;
      final sent = (booked.trip['pickup'] as Map)['address'] as String?;
      // The trip names the pickup as Set pickup confirmed it.
      expect(sent, booked.address);
      expect(isUnusablePickupLabel(sent), isFalse);
      expect(_rawCoordinates.hasMatch(sent ?? ''), isFalse);
      expect(
        (booked.trip['pickup'] as Map)['lat'],
        closeTo(_moved.latitude, 0.005),
      );
      // Not in any price request either: the server keeps what it is sent.
      for (final address in server.pickupAddresses) {
        expect(_rawCoordinates.hasMatch(address ?? ''), isFalse);
      }
      await close(tester);
    },
  );

  testWidgets(
    'when the price cannot be asked again under the confirmed address, the '
    'ride is still booked, as a dropped pin, never as bare coordinates',
    (tester) async {
      final server = _Server();
      final booking = await pumpSelectRide(tester, server);
      await tester.tap(find.text('Select Movera'));
      await settle(tester, 30);
      await movePin(tester);
      server.down = true;
      await confirm(tester);

      expect(booking.bookings, hasLength(1));
      final sent =
          (booking.bookings.single.trip['pickup'] as Map)['address'] as String?;
      expect(_rawCoordinates.hasMatch(sent ?? ''), isFalse);
      expect(isDroppedPinLabel(sent), isTrue);
      await close(tester);
    },
  );

  testWidgets(
    'an unmoved pickup is booked with the list price: no new request',
    (tester) async {
      final server = _Server();
      final booking = await pumpSelectRide(tester, server);
      await tester.tap(find.text('Select Movera'));
      await settle(tester, 30);
      final asked = server.quoteBodies.length;
      await confirm(tester);

      expect(booking.bookings, hasLength(1));
      expect(server.quoteBodies, hasLength(asked));
      expect(
        (booking.bookings.single.trip['pickup'] as Map)['address'],
        'Drottninggatan 1, Stockholm',
      );
      await close(tester);
    },
  );
}

Future<void> settle(WidgetTester tester, [int steps = 10]) async {
  for (var i = 0; i < steps; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
