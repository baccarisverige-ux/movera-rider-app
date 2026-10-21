import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/notifications/push_payload.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/app/screen_scale.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_sheet_bits.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/finding_driver/presentation/finding_drivers.dart';
import 'package:movera_rider/features/notifications/application/notifications_controller.dart';
import 'package:movera_rider/features/notifications/data/notifications_repository.dart';
import 'package:movera_rider/features/notifications/presentation/notifications.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
}
