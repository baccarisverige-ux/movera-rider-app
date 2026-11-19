import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/app/router/routes.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/finding_driver/presentation/finding_drivers.dart';
import 'package:movera_rider/features/profile/domain/rider_outstanding.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:movera_rider/features/ride_booking/application/ride_restore_coordinator.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/shared/widgets/navigation_transition.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Debt line M2 (owner 2026-11-19 "Yes, build M2 + M3"): the search card
/// shows the same unpaid-fee row as the ride on board, under its payment
/// line, and nothing when the rider owes nothing. Fail-before on main
/// 41919f46: no `trip-debt-box`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    RideSnapshotStore.epoch = 0;
    FindingDriverController.active = null;
    L10n.use('sv');
    RiderOutstanding.reset();
  });
  tearDown(() {
    L10n.use('en');
    RiderOutstanding.reset();
    RiderOutstanding.refresher = null;
  });

  const rideId = 'm2-finding';

  Future<void> openFinding(WidgetTester tester, List<Money> owed) async {
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    RideRestoreCoordinator.instance.showing = RestoredSurface.home;
    final server = InProcessMockClient();
    final api = ApiClient(client: server);
    final realtime = MockRideRealtime(
      assignAfter: const Duration(days: 1),
      api: api,
    );
    addTearDown(realtime.dispose);
    server.rides[rideId] = {
      'id': rideId,
      'status': 'findingDriver',
      'version': 1,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
      'categoryId': 'economy',
      'paymentMethodId': 'cash',
    };
    AppScope.instance.ride
      ..rideId = rideId
      ..status = RideStatus.findingDriver
      ..suppressRestore = false
      ..authoritativeVersion = 1
      ..bookedCategoryId = 'economy'
      ..bookedPaymentMethodId = 'cash';
    // After AppScope exists (it sets its own reader): the server's answer.
    RiderOutstanding.refresher = () async {
      RiderOutstanding.current.value = RiderOutstanding(byCurrency: owed);
      return true;
    };
    final controller = FindingDriverController(realtime: realtime, api: api);
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(375, 812),
        minTextAdapt: true,
        splitScreenMode: true,
        builder: (_, __) => MaterialApp(
          navigatorKey: nav,
          home: const Scaffold(body: Center(child: Text('m2-home'))),
        ),
      ),
    );
    nav.currentState!.push(
      RideStageTransition(
        FindingDrivers(
          pickupAddress: 'Klockarvägen 37, Södertälje',
          destinationAddress: 'Gullmarsplan, Johanneshov',
          pickupPosition: const LatLng(59.1962, 17.6279),
          destinationPosition: const LatLng(59.33, 18.0587),
          rideType: 'Movera',
          price: 215,
          paymentMethod: 'cash',
          realtime: realtime,
          searchStartedAt: DateTime.now(),
          controller: controller,
        ),
        settings: const RouteSettings(name: AppRoutes.findingDriver),
      ),
    );
    await tester.pump();
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  const box = ValueKey<String>('trip-debt-box');
  const total = ValueKey<String>('trip-debt-total');

  testWidgets('Sara owes 35 kr: the row is under the 215 kr line', (
    tester,
  ) async {
    await openFinding(tester, const [Money(3500, 'SEK')]);
    final line = find.textContaining('215,00 kr');
    expect(line, findsOneWidget);
    expect(tester.widget<Text>(line).data, 'Betala i bilen  ·  215,00 kr');
    expect(find.byKey(box), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(total)).data, '250,00\u00A0kr');
    expect(
      tester.getTopLeft(find.byKey(box)).dy,
      greaterThan(tester.getBottomLeft(line).dy),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('no debt, or a debt in euros: the card is as before', (
    tester,
  ) async {
    await openFinding(tester, const [Money(350, 'EUR')]);
    expect(find.textContaining('215,00 kr'), findsOneWidget);
    expect(find.byKey(box), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
