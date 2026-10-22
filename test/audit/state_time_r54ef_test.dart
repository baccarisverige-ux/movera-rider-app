import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/contracts/server_clock.dart';
import 'package:movera_rider/core/feature_flags/feature_flags.dart';
import 'package:movera_rider/core/location/geocoding_repository.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/booking/application/booking_controller.dart';
import 'package:movera_rider/features/payments/application/card_entry_policy.dart';
import 'package:movera_rider/features/payments/presentation/add_card_page.dart';
import 'package:movera_rider/features/pickup/presentation/set_pickup_page.dart';
import 'package:movera_rider/features/ride_booking/data/mock_quote_repository.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/quote.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_notes.dart';
import 'package:movera_rider/features/ride_booking/domain/route_stop.dart';
import 'package:movera_rider/features/ride_selection/application/ride_catalog_controller.dart';
import 'package:movera_rider/features/ride_selection/application/ride_selection_controller.dart';
import 'package:movera_rider/features/ride_selection/data/ride_catalog_cache.dart';
import 'package:movera_rider/features/ride_selection/presentation/select_ride.dart';
import 'package:movera_rider/shared/widgets/custom_google_map.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/api/safety_mock_api.dart';
import 'package:movera_rider/core/contracts/ride_status.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/core/realtime/ride_realtime.dart';
import 'package:movera_rider/features/profile/application/account_security_controller.dart';
import 'package:movera_rider/features/profile/data/account_security_repository.dart';
import 'package:movera_rider/features/profile/presentation/security.dart';
import 'package:movera_rider/features/promotions/domain/rider_promotion.dart';
import 'package:movera_rider/features/promotions/presentation/promotion_details_sheet.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/data/local_reservation_repository.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/domain/reservation_status.dart';
import 'package:movera_rider/features/reservations/presentation/reservation_format.dart';
import 'package:movera_rider/features/ride_booking/application/ride_restore_coordinator.dart';
import 'package:movera_rider/features/ride_booking/application/ride_session.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/safety/application/emergency_call_service.dart';
import 'package:movera_rider/features/safety/application/ride_check_controller.dart';
import 'package:movera_rider/features/safety/application/safety_controller.dart';
import 'package:movera_rider/features/safety/data/safety_data_sources.dart';
import 'package:movera_rider/features/safety/data/safety_repository.dart';
import 'package:movera_rider/features/safety/data/safety_store.dart';
import 'package:movera_rider/features/safety/domain/ride_check.dart';
import 'package:movera_rider/features/safety/domain/ride_check_monitor.dart';
import 'package:movera_rider/features/safety/domain/ride_check_record.dart';
import 'package:movera_rider/features/safety/domain/ride_check_trigger.dart';
import 'package:movera_rider/features/saved_places/presentation/pickup_location.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:movera_rider/shared/widgets/horizontal_swipe.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Wave 5 R5.4 parts e + f: state and time (low). One test per bug.

const _origin = LatLng(59.3293, 18.0686);
const _moved = LatLng(59.31, 18.0686);

/// Every ride costs 42 kr more from the moved pin. [slowPin] holds the
/// first moved-pin quote until [pin] completes.
class _Quotes implements QuoteRepository {
  _Quotes({this.slowPin = false});

  final bool slowPin;
  Completer<void>? pin;
  bool _pinSeen = false;
  int calls = 0;

  @override
  Future<RideQuote> quote({
    required String rideType,
    required int distanceMeters,
    int durationSeconds = 600,
    String? pickup,
    String? destination,
    GeoPoint? pickupPoint,
    GeoPoint? destinationPoint,
    List<RouteStop> stops = const <RouteStop>[],
  }) async {
    calls++;
    final id = calls;
    final atOrigin =
        pickupPoint == null ||
        (pickupPoint.latitude - _origin.latitude).abs() < 1e-6;
    if (!atOrigin && !_pinSeen) {
      _pinSeen = true;
      if (slowPin) await (pin = Completer<void>()).future;
    }
    final base = rideType == 'comfort' ? 33900 : 25900;
    return RideQuote(
      id: 'q-$rideType-$id-${atOrigin ? 'OLD' : 'NEW'}',
      rideType: rideType,
      totalMinor: base + (atOrigin ? 0 : 4200),
      currency: 'SEK',
      expiresAt: ServerClock.now().add(const Duration(minutes: 2)),
      signedPayload: 'signature',
    );
  }
}

/// Records what would be booked, then stops there.
class _Booking extends BookingController {
  final List<({String ride, String quote, String pay, DateTime? expires})>
  booked = [];

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
    booked.add((
      ride: rideType,
      quote: quoteId ?? '',
      pay: paymentMethod,
      expires: quoteExpiresAt,
    ));
    throw StateError('stop here');
  }
}

/// The ride-types endpoint fails until [serve] lists [ids].
class _Catalog {
  bool serve = false;
  List<String> ids = const ['economy', 'comfort'];

  ApiClient get api => ApiClient(
    client: MockClient((_) async {
      if (!serve) {
        return http.Response(jsonEncode({'code': 'X'}), 500);
      }
      return http.Response(
        jsonEncode({
          'rideTypes': [
            for (final id in ids)
              {
                'id': id,
                'name': id == 'economy' ? 'Movera' : 'Comfort',
                'price': id == 'economy' ? 259 : 339,
              },
          ],
        }),
        200,
      );
    }),
  );
}

RideSelectionController _selection(
  QuoteRepository quotes, {
  _Catalog? catalog,
}) {
  final selection = RideSelectionController(
    catalog: RideCatalogController(
      api: (catalog ?? _Catalog()).api,
      cache: MemoryRideCatalogCache(),
    ),
    quotes: quotes,
    flags: FeatureFlags(),
  );
  addTearDown(selection.dispose);
  return selection;
}

Future<void> _settle(WidgetTester tester, [int steps = 10]) async {
  for (var i = 0; i < steps; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pumpSelectRide(
  WidgetTester tester,
  RideSelectionController selection,
  _Booking booking,
) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: SelectRide(
        pickupAddress: 'Klockarvägen 37',
        destinationAddress: 'Arlanda Airport',
        pickupPosition: _origin,
        destinationPosition: const LatLng(59.6519, 17.9186),
        selection: selection,
        booking: booking,
      ),
    ),
  );
  await _settle(tester);
}

/// Book now on Movera, then drag Set pickup's pin to [_moved].
Future<void> _openSetPickupAndMovePin(WidgetTester tester) async {
  await tester.tap(find.text('Select Movera'));
  await _settle(tester, 30);
  expect(find.byType(SetPickupPage), findsOneWidget);
  final map = tester.widget<CustomGoogleMap>(
    find.byKey(const ValueKey('set-pickup-map')),
  );
  map.onCameraMoveStarted!();
  map.onCameraMove!(const CameraPosition(target: _moved, zoom: 16));
  map.onCameraIdle!();
  await tester.pump();
}

Future<void> _confirmPickup(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('set-pickup-confirm')));
  await _settle(tester, 40);
}

Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 10));
}

/// Polls (real time, no fixed wait) until [done] holds or 5 s pass.
Future<bool> _eventually(FutureOr<bool> Function() done) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!await done()) {
    if (DateTime.now().isAfter(deadline)) return false;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  return true;
}

/// Holds every Ride check answers POST until [release].
class _SlowAnswers extends InProcessMockClient {
  final _held = <Completer<void>>[];

  void release() {
    for (final held in _held) {
      if (!held.isCompleted) held.complete();
    }
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.path == '/api/v1/safety/ridecheck/answers') {
      final held = Completer<void>();
      _held.add(held);
      await held.future;
    }
    return super.send(request);
  }
}

/// One app launch over the device's stored Safety data.
Future<(SafetyStore, RideCheckController)> _launchSafety(
  InProcessMockClient client,
) async {
  SafetyStore.resetShared();
  SafetyRepository.resetShared();
  SafetyController.resetShared();
  final store = SafetyStore(
    local: PreferencesSafetyLocalDataSource(),
    remote: ApiSafetyRemoteDataSource(ApiClient(client: client)),
  );
  final safety = SafetyController(
    session: store,
    emergency: EmergencyCallService(dialer: RecordingEmergencyDialer()),
  );
  await safety.load();
  final rideCheck = RideCheckController.forSafety(safety);
  rideCheck.attachTrip(
    const RideCheckTripContext(rideId: 'ride_u197', status: 'tripInProgress'),
    const RideCheckPlan(
      pickup: GeoPoint(59.3429, 18.0496),
      destination: GeoPoint(59.3600, 18.0000),
    ),
  );
  return (store, rideCheck);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('rider-u155: Last changed is the rider\'s local day', (
    tester,
  ) async {
    final client = InProcessMockClient();
    final stamp = DateTime.utc(2026, 3, 10, 23, 30);
    client.accountSecurity['passwordUpdatedAt'] = stamp.toIso8601String();
    (client.accountSecurity['capabilities'] as Map)['password'] = true;
    final security = AccountSecurityController(
      repository: AccountSecurityRepository(api: ApiClient(client: client)),
    );
    await tester.runAsync(security.load);
    await tester.pumpWidget(
      MaterialApp(home: SecurityPage(securityController: security)),
    );
    await tester.pumpAndSettle();
    final local = L10n.formatDate(stamp.toLocal(), 'yMd');
    expect(find.text('Last changed $local'), findsOneWidget);
  });

  test('rider-u158: days left counts calendar days across spring-forward', () {
    final promotion = RiderPromotion(
      id: 'p',
      title: 'Spring',
      percentOff: 10,
      ridesLeft: 1,
      ridesTotal: 1,
      endsAt: DateTime(2026, 3, 30, 18),
    );
    expect(
      PromotionDetailsSheet.validityText(promotion, DateTime(2026, 3, 29, 12)),
      L10n.current.validUntilDays(
        L10n.formatDate(DateTime(2026, 3, 30), 'd MMM y'),
        1,
      ),
    );
  });

  test('rider-64: the day after the spring-forward day is Tomorrow', () {
    final monday = DateTime(2026, 3, 30, 10);
    expect(
      ReservationFormat.cardDate(monday, now: DateTime(2026, 3, 29, 12)),
      startsWith(L10n.current.tomorrowDate('').trim()),
    );
  });

  test('rider-j8-9: a ride waiting for a driver moved to tomorrow is '
      'scheduled again', () async {
    final now = DateTime(2026, 10, 22, 10);
    final reservations = ReservationController(
      store: LocalReservationRepository(
        storage: MemoryReservationStorage(),
        clock: () => now,
      ),
      clock: () => now,
    );
    const place = ReservationPlace(label: 'A', lat: 59.33, lng: 18.06);
    final ride = await reservations.create(
      ReservationDraft(
        scheduledPickupAt: now.add(const Duration(minutes: 1)),
        pickup: place,
        destination: place,
        categoryId: 'economy',
        categoryName: 'Movera',
        categoryImage: '',
        price: 259,
        paymentMethod: 'cash',
      ),
    );
    await reservations.startLiveIfDue(now: now);
    expect(
      reservations.byId(ride.reservationId)!.status,
      ReservationStatus.driverAssignmentPending,
    );
    final moved = await reservations.update(
      ride.reservationId,
      ReservationPatch(scheduledPickupAt: now.add(const Duration(days: 1))),
    );
    expect(moved.status, ReservationStatus.scheduled);
  });

  test(
    'rider-u173: a restored completion screen goes on from its stage',
    () async {
      SharedPreferences.setMockInitialValues({});
      final snapshot = RideSnapshot(
        status: RideStatus.paymentFinalized,
        savedAt: DateTime.now(),
        pickupAddress: 'A',
        destinationAddress: 'B',
        pickupLat: 59.33,
        pickupLng: 18.06,
        destinationLat: 59.34,
        destinationLng: 18.07,
        rideType: 'Movera',
        price: 259,
        paymentMethod: 'cash',
        rideId: 'ride_u173',
        version: 9,
      );
      RideRestoreCoordinator(
        skipRestore: () => false,
        authRequired: () => false,
        serverActiveTrip: () async => null,
      ).pageFor(snapshot);
      final realtime = AppScope.instance.rideRealtime as MockRideRealtime;
      final seen = <RideStatus>[];
      final sub = realtime
          .subscribe('ride_u173')
          .listen((e) => seen.add(e.status));
      addTearDown(sub.cancel);
      expect(
        await _eventually(() => seen.contains(RideStatus.ratingPending)),
        isTrue,
        reason: 'seen: $seen',
      );
      expect(seen.first, RideStatus.paymentFinalized);
      expect(seen, isNot(contains(RideStatus.findingDriver)));
    },
  );

  test('rider-69: an illegal backend jump logs ride.restore.jump', () {
    final printed = <String>[];
    final previous = debugPrint;
    debugPrint = (message, {wrapWidth}) => printed.add(message ?? '');
    addTearDown(() => debugPrint = previous);
    final session = RideSession(rideId: 'ride_69')
      ..status = RideStatus.driverArriving;
    session.backendReconcile(
      RideStatus.paymentFinalized,
      id: 'ride_69',
      version: 4,
    );
    expect(session.status, RideStatus.paymentFinalized);
    expect(
      printed.where((line) => line.contains('ride.restore.jump')),
      isNotEmpty,
    );
  });
}
