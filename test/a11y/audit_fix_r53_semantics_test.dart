import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/feature_flags/feature_flags.dart';
import 'package:movera_rider/core/location/geocoding_repository.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/core/notifications/push_payload.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/core/realtime/realtime_connection.dart';
import 'package:movera_rider/app/screen_scale.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_sheet_bits.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/finding_driver/presentation/finding_drivers.dart';
import 'package:movera_rider/features/notifications/application/notifications_controller.dart';
import 'package:movera_rider/features/notifications/data/notifications_repository.dart';
import 'package:movera_rider/features/notifications/presentation/notifications.dart';
import 'package:movera_rider/features/profile/presentation/account_widgets.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/data/local_reservation_repository.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/presentation/ride_scheduled.dart';
import 'package:movera_rider/features/reservations/presentation/upcoming_reservation.dart';
import 'package:movera_rider/features/scheduled_rides/application/scheduled_rides_controller.dart';
import 'package:movera_rider/features/scheduled_rides/presentation/schedule_ride.dart';
import 'package:movera_rider/features/scheduled_rides/presentation/select_date_time.dart';
import 'package:movera_rider/features/ride_booking/data/mock_quote_repository.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/quote.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/ride_booking/domain/route_stop.dart';
import 'package:movera_rider/features/ride_selection/application/ride_catalog_controller.dart';
import 'package:movera_rider/features/ride_selection/application/ride_selection_controller.dart';
import 'package:movera_rider/features/ride_selection/data/ride_catalog_cache.dart';
import 'package:movera_rider/features/ride_selection/presentation/select_ride.dart';
import 'package:movera_rider/features/safety/presentation/ride_safety_kit.dart';
import 'package:movera_rider/features/saved_places/presentation/add_place.dart';
import 'package:movera_rider/features/saved_places/presentation/pickup_location.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:movera_rider/shared/design_system/movera_empty_state.dart';
import 'package:movera_rider/shared/widgets/realtime_connection_banner.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Geocoder implements GeocodingRepository {
  @override
  Future<PlaceResult?> forward(String query) async =>
      PlaceResult(address: query, point: const GeoPoint(59.35, 18.07));

  @override
  Future<String?> reverse(GeoPoint point) async => null;
}

class _Quotes implements QuoteRepository {
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
  }) async => RideQuote(
    id: 'q-$rideType',
    rideType: rideType,
    totalMinor: 25900,
    currency: 'SEK',
    expiresAt: DateTime.now().add(const Duration(minutes: 5)),
    signedPayload: 'signature',
  );
}

/// Wave 5 R5.3: small semantics checks (label, tap action, value, size)
/// for the accessibility fixes, one case per bug.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Future<void> pump(
    WidgetTester tester,
    Widget home, {
    Size size = const Size(390, 844),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MoveraScreenUtilInit(
        builder: (_, __) => MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: home,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('rider-u64: Share trip is a 44 px named button', (tester) async {
    await pump(
      tester,
      const Scaffold(body: Center(child: WaitingShareButton())),
    );
    final handle = tester.ensureSemantics();
    final share = find.bySemanticsLabel('Share trip');
    expect(tester.getSize(share).shortestSide, greaterThanOrEqualTo(44));
    expect(
      tester.getSemantics(share),
      isSemantics(
        label: 'Share trip',
        isButton: true,
        hasTapAction: true,
      ),
    );
    handle.dispose();
  });

  testWidgets('rider-u110: the raise-offer sheet leaves Cancel uncovered '
      'on a short viewport', (tester) async {
    const rideId = 'a11y-price-bump';
    final server = InProcessMockClient();
    server.rides[rideId] = {'id': rideId, 'status': 'searching'};
    AppScope.instance.ride
      ..rideId = rideId
      ..status = RideStatus.findingDriver
      ..suppressRestore = false;
    final realtime = MockRideRealtime(assignAfter: const Duration(days: 1));
    final controller = FindingDriverController(
      realtime: realtime,
      api: ApiClient(client: server),
      priceBumpAfter: const Duration(seconds: 1),
    );
    // iPhone SE in Safari: about 375 x 548.
    await pump(
      tester,
      FindingDrivers(
        pickupAddress: 'Stockholm Central',
        destinationAddress: 'Arlanda Airport',
        pickupPosition: const LatLng(59.33, 18.059),
        destinationPosition: const LatLng(59.6519, 17.9186),
        rideType: 'Movera',
        price: 349,
        paymentMethod: 'Apple Pay',
        realtime: realtime,
        controller: controller,
      ),
      size: const Size(375, 548),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(controller.showPriceBump, isTrue);

    final handle = find.byWidgetPredicate(
      (w) =>
          w is DecoratedBox &&
          w.decoration is BoxDecoration &&
          (w.decoration as BoxDecoration).color == const Color(0xFFE7EBEE),
    );
    // Any touch on the sheet settles it on its stops (the card's 520 px).
    await tester.drag(handle.first, const Offset(0, -20));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    expect(tester.getRect(handle.first).top, greaterThanOrEqualTo(56));
    final close = find.byIcon(Icons.close_rounded).first;
    final hits = tester.hitTestOnBinding(tester.getCenter(close));
    expect(
      hits.path.any((entry) => entry.target == tester.renderObject(close)),
      isTrue,
      reason: 'the sheet paints over the Cancel button',
    );

    realtime.dispose();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('rider-u130: an unread notification is announced as unread', (
    tester,
  ) async {
    final controller = NotificationsController(store: NotificationsRepository())
      ..ingest(
        const PushPayload(
          type: 'ride.completed',
          title: 'New one',
          body: 'Not read yet.',
          messageId: 'a11y-unread',
        ),
        read: false,
      )
      ..ingest(
        const PushPayload(
          type: 'ride.completed',
          title: 'Old one',
          body: 'Already read.',
          messageId: 'a11y-read',
        ),
        read: true,
      );
    final handle = tester.ensureSemantics();
    await pump(tester, NotificationScreen(controller: controller));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('New one'), findsOneWidget);
    expect(find.text('Old one'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Unread')), findsOneWidget);
    expect(
      tester.getSemantics(find.bySemanticsLabel(RegExp('Unread'))).label,
      contains('New one'),
    );
    handle.dispose();
  });

  testWidgets('rider-u151: a choice sheet marks the current option selected', (
    tester,
  ) async {
    await pump(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showAccountChoice(
              context,
              title: 'Language',
              options: const ['English', 'Français', 'Svenska'],
              selected: 'Svenska',
            ),
            child: const Text('open-choice'),
          ),
        ),
      ),
    );
    final handle = tester.ensureSemantics();
    await tester.tap(find.text('open-choice'));
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(find.text('Svenska')),
      isSemantics(isSelected: true, hasSelectedState: true, hasTapAction: true),
    );
    expect(
      tester.getSemantics(find.text('English')),
      isSemantics(isSelected: false, hasTapAction: true),
    );
    handle.dispose();
  });

  testWidgets('rider-u167: scheduling close and back buttons are named and '
      'at least 44 px', (tester) async {
    final handle = tester.ensureSemantics();
    void expectNamedButton(String label) {
      final node = find.bySemanticsLabel(label);
      expect(node, findsOneWidget, reason: label);
      expect(
        tester.getSemantics(node),
        isSemantics(isButton: true, hasTapAction: true),
      );
      expect(tester.getSize(node).shortestSide, greaterThanOrEqualTo(44));
    }

    final reservations = ReservationController(
      store: LocalReservationRepository(storage: MemoryReservationStorage()),
    );
    final ride = await reservations.create(
      ReservationDraft(
        scheduledPickupAt: DateTime.now().add(const Duration(days: 1)),
        pickup: const ReservationPlace(label: 'Home'),
        destination: const ReservationPlace(label: 'Arlanda Express'),
        categoryId: 'economy',
        categoryName: 'Movera',
        categoryImage: 'assets/images/rides/movera.webp',
        price: 522,
        paymentMethod: 'Card',
      ),
    );
    await pump(
      tester,
      RideScheduledPage(
        reservationId: ride.reservationId,
        controller: reservations,
      ),
    );
    expectNamedButton('Close');

    await pump(
      tester,
      ScheduleDateTimeSelector(
        body: const SizedBox.shrink(),
        session: ScheduledRideSession(),
        onConfirm: () {},
      ),
    );
    expectNamedButton('Back');

    await pump(tester, const ScheduleRide());
    expectNamedButton('Back');
    handle.dispose();
  });

  testWidgets('rider-68: the driver card reads the plate in the app language',
      (tester) async {
    L10n.use('sv');
    addTearDown(() => L10n.use('en'));
    final handle = tester.ensureSemantics();
    await pump(
      tester,
      const Scaffold(
        body: ReservationDriverCard(
          driver: ReservationDriver(firstName: 'Anna', plate: 'ABC 123'),
        ),
      ),
    );
    final card = find.bySemanticsLabel(RegExp('Anna'));
    final label = tester.getSemantics(card).label;
    expect(label, contains('registreringsnummer ABC 123'));
    expect(label, isNot(contains('plate')));
    expect(L10n.current.restoringRide, isNot('Restoring active ride'));
    handle.dispose();
  });

  testWidgets('rider-u191: Select ride filters and tiles announce selection',
      (tester) async {
    final selection = RideSelectionController(
      catalog: RideCatalogController(
        api: ApiClient(
          client: MockClient(
            (_) async => http.Response(jsonEncode({'code': 'X'}), 500),
          ),
        ),
        cache: MemoryRideCatalogCache(),
      ),
      quotes: _Quotes(),
      flags: FeatureFlags(),
    );
    addTearDown(selection.dispose);
    final handle = tester.ensureSemantics();
    await pump(
      tester,
      SelectRide(
        pickupAddress: 'Klockarvägen 37',
        destinationAddress: 'Arlanda Airport',
        pickupPosition: const LatLng(59.3293, 18.0686),
        destinationPosition: const LatLng(59.6519, 17.9186),
        geocoding: _Geocoder(),
        selection: selection,
        reservations: ReservationController(
          store: LocalReservationRepository(storage: MemoryReservationStorage()),
        ),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    SemanticsNode nodeOf(Finder text) => tester.getSemantics(text.first);

    // The filters show on the fully open sheet.
    await tester.tap(find.byKey(const ValueKey('select-ride-sheet-handle')));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    final recommended = find.text('Recommended');
    final faster = find.text('Faster');
    expect(nodeOf(recommended), isSemantics(isButton: true, isSelected: true));
    expect(nodeOf(faster), isSemantics(isButton: true, isSelected: false));
    expect(nodeOf(faster).rect.height, greaterThanOrEqualTo(44));
    await tester.tap(faster);
    await tester.pump();
    expect(nodeOf(faster), isSemantics(isButton: true, isSelected: true));

    // The chosen category's tile is selected; another one is not.
    final chosen = selection.rideById(selection.selectedRideId).name;
    final tiles = find.ancestor(
      of: find.text(chosen),
      matching: find.byType(InkWell),
    );
    expect(
      tester.getSemantics(tiles.first),
      isSemantics(isButton: true, isSelected: true, hasTapAction: true),
    );
    handle.dispose();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('rider-u216: the Safety Kit sheet scrolls at 2x text instead '
      'of clipping Safety preferences', (tester) async {
    L10n.use('fr');
    addTearDown(() => L10n.use('en'));
    await pump(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showRideSafetyKit(context, rideId: 'ride-a11y'),
            child: const Text('open-kit'),
          ),
        ),
      ),
      size: const Size(375, 667),
      textScale: 2,
    );
    await tester.tap(find.text('open-kit'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.takeException(), isNull, reason: 'no RenderFlex overflow');
    final prefs = find.text('Préférences de sécurité');
    await tester.ensureVisible(prefs);
    await tester.pump();
    expect(tester.getRect(prefs).bottom, lessThanOrEqualTo(667));
    expect(tester.takeException(), isNull);
  });

  testWidgets('rider-u221: Add place scrolls on a small phone with the '
      'keyboard up and the error shown', (tester) async {
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    addTearDown(tester.view.resetViewInsets);
    await pump(tester, const AddPlace(), size: const Size(320, 568), textScale: 1.3);
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(find.text('Add both a name and a location.'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'no RenderFlex overflow');
    await tester.ensureVisible(find.text('Save'));
    await tester.pump();
    expect(tester.getRect(find.text('Save')).bottom, lessThanOrEqualTo(568 - 260));
  });

  testWidgets('rider-u224: the saved-place picker close is a named 44 px '
      'button', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(
      tester,
      const RiderSearchPickupLocation(),
      size: const Size(320, 568),
    );
    final close = find.bySemanticsLabel('Close');
    expect(close, findsOneWidget);
    expect(
      tester.getSemantics(close),
      isSemantics(isButton: true, hasTapAction: true),
    );
    expect(tester.getSize(close).shortestSide, greaterThanOrEqualTo(44));
    handle.dispose();
  });

  testWidgets('rider-j8-16: the connection banner and empty state are read '
      'once', (tester) async {
    final handle = tester.ensureSemantics();
    final connection = RealtimeConnection()..markReconnecting();
    await pump(
      tester,
      Scaffold(body: RealtimeConnectionBanner(connection: connection)),
    );
    await tester.pump(const Duration(milliseconds: 300));
    final title = L10n.current.rtReconnecting;
    final body = L10n.current.rtReconnectingBody;
    final banner = find.bySemanticsLabel(RegExp(RegExp.escape(body)));
    expect(banner, findsOneWidget);
    expect(tester.getSemantics(banner).label, '$title. $body');

    await pump(
      tester,
      const Scaffold(
        body: MoveraEmptyState(
          icon: Icons.history_rounded,
          title: 'No rides yet',
          message: 'Your trips will show here.',
        ),
      ),
    );
    final empty = find.bySemanticsLabel(RegExp('No rides yet'));
    expect(empty, findsOneWidget);
    expect(
      tester.getSemantics(empty).label,
      'No rides yet. Your trips will show here.',
    );
    handle.dispose();
  });
}
