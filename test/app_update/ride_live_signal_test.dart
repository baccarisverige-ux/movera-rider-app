import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/app_update/min_app_version.dart';
import 'package:movera_rider/core/app_update/ride_live_signal.dart';
import 'package:movera_rider/core/content/rider_content_controller.dart';
import 'package:movera_rider/features/content/presentation/content_gate.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Contract v0.18.154 P16c review (rider #684 MUST): the "ride is live"
/// signal for the minimum-version block, with the real RideSnapshotStore
/// and RideLiveSignal: a live booked ride (no snapshot) blocks nothing, a
/// cold start with a stored live ride blocks nothing, the after-ride
/// screens block nothing, and nothing blocks until the app knows.
class _RideScreen extends StatefulWidget {
  const _RideScreen();
  @override
  State<_RideScreen> createState() => _RideScreenState();
}

/// Uses the same mixin as WaitingForDriver (on-demand and booked live
/// ride), FindingDrivers and RideCompleted.
class _RideScreenState extends State<_RideScreen>
    with RideScreenLive<_RideScreen> {
  @override
  Widget build(BuildContext context) => const Text('Ride screen');
}

RideSnapshot _snapshot(RideStatus status) => RideSnapshot(
  status: status,
  savedAt: DateTime.now(),
  pickupAddress: 'A',
  destinationAddress: 'B',
  pickupLat: 59.34,
  pickupLng: 18.05,
  destinationLat: 59.31,
  destinationLng: 18.04,
  rideType: 'Movera',
  price: 259,
  paymentMethod: 'Cash',
  rideId: 'ride_p16c',
);

void main() {
  const screen = Key('min-version-required');
  late RideLiveSignal signal;
  var serverLive = false;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    RideSnapshotStore.epoch = 0;
    serverLive = false;
    MinAppVersion.reset();
    MinAppVersion.running = '1.4.0';
    MinAppVersion.platform = 'android';
    signal = RideLiveSignal.instance = RideLiveSignal(
      snapshotLive: RideSnapshotStore.rideLive,
      storedLive: () async {
        final stored = await RideSnapshotStore.read();
        return stored != null && !stored.status.isTerminal;
      },
      serverLive: () async => serverLive,
    );
  });
  tearDown(() {
    signal.dispose();
    RideLiveSignal.instance = null;
    MinAppVersion.reset();
  });

  Future<void> pump(WidgetTester tester, {bool rideScreen = false}) async {
    L10n.use('en');
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => ContentGate(
          controller: RiderContentController(),
          rideLive: signal,
          onCallEmergency: () {},
          onOpenStore: () {},
          child: child!,
        ),
        home: rideScreen ? const _RideScreen() : const Text('Home'),
      ),
    );
  }

  Future<void> belowMin(WidgetTester tester) async {
    await tester.runAsync(() async {
      MinAppVersion.accept({
        'minVersion': {'android': '1.5.0'},
      });
      await signal.check();
    });
    await tester.pump();
  }

  testWidgets('no ride (confirmed): the block', (tester) async {
    await pump(tester);
    expect(find.byKey(screen), findsNothing, reason: 'unknown never blocks');
    await belowMin(tester);
    expect(signal.known, isTrue);
    expect(find.byKey(screen), findsOneWidget);
  });

  testWidgets('a live booked ride (its screen saves no snapshot): no block', (
    tester,
  ) async {
    await pump(tester, rideScreen: true);
    await belowMin(tester);
    expect(RideSnapshotStore.rideLive.value, isFalse);
    await tester.pump();
    expect(find.byKey(screen), findsNothing);
    expect(find.text('Ride screen'), findsOneWidget);
  });

  testWidgets('a cold start with a stored live ride: no block', (tester) async {
    await tester.runAsync(
      () => RideSnapshotStore.save(_snapshot(RideStatus.findingDriver)),
    );
    // A new process: the store's flag starts false, the stored ride stays.
    RideSnapshotStore.epoch = 0;
    expect(RideSnapshotStore.rideLive.value, isFalse);
    await pump(tester);
    await belowMin(tester);
    expect(find.byKey(screen), findsNothing);
  });

  testWidgets('a cold start with a server active trip: no block', (
    tester,
  ) async {
    serverLive = true;
    await pump(tester);
    await belowMin(tester);
    expect(find.byKey(screen), findsNothing);
  });

  testWidgets(
    'after the ride: no block on the rating / tip screen, then Home',
    (tester) async {
      await pump(tester, rideScreen: true);
      await belowMin(tester);
      await tester.runAsync(
        () => RideSnapshotStore.save(_snapshot(RideStatus.closed)),
      );
      await tester.pump();
      expect(find.byKey(screen), findsNothing);
      await pump(tester);
      await tester.pump();
      expect(find.byKey(screen), findsOneWidget);
    },
  );

  test('a 426 with an unreadable body or another reason does not block', () {
    MinAppVersion.markServerSaid(null);
    MinAppVersion.markServerSaid({'reason': 'other'});
    expect(MinAppVersion.required, isFalse);
  });
}
