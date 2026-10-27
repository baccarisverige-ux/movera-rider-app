import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/location/geocoding_repository.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/features/active_ride/application/route_change_controller.dart';
import 'package:movera_rider/features/active_ride/presentation/route_change_flow.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/finding_driver/data/finding_driver_repository.dart';
import 'package:movera_rider/features/profile/data/account_security_repository.dart';
import 'package:movera_rider/features/ride_complete/data/ride_dispute_repository.dart';
import 'package:movera_rider/features/support/application/support_contact.dart';
import 'package:movera_rider/features/support/domain/support.dart';
import 'package:movera_rider/features/support/presentation/support.dart';
import 'package:movera_rider/features/ride_booking/application/ride_session.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/safety/application/safety_controller.dart';
import 'package:movera_rider/features/safety/data/safety_repository.dart';
import 'package:movera_rider/features/safety/data/safety_store.dart';
import 'package:movera_rider/features/safety/presentation/safety_hub.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Audit Phase 5: calls the live rider build made to paths movera-server
/// does not serve (measured on the staging build against a local server:
/// every one answered 404). On the contract wire none is sent now, and the
/// screens say the feature is not available instead of failing on save.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  const live = AppEnv(
    flavor: AppFlavor.staging,
    apiBaseUrl: 'https://x.invalid',
  );
  const demo = AppEnv(flavor: AppFlavor.demo, apiBaseUrl: 'https://x.invalid');

  ({ApiClient api, List<String> calls}) recording(AppEnv env) {
    final calls = <String>[];
    final api = ApiClient(
      env: env,
      client: MockClient((request) async {
        calls.add('${request.method} ${request.url.path}');
        return http.Response(
          '{"code":"not_found","message":"Not found."}',
          404,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    return (api: api, calls: calls);
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RideSnapshotStore.epoch = 0;
    SafetyStore.resetShared();
    SafetyRepository.resetShared();
    SafetyController.resetShared();
  });

  RideSnapshot ride() => RideSnapshot(
    status: RideStatus.tripInProgress,
    savedAt: DateTime.now(),
    pickupAddress: 'Sergels torg',
    destinationAddress: 'Odenplan',
    pickupLat: 59.3326,
    pickupLng: 18.0649,
    destinationLat: 59.3429,
    destinationLng: 18.0496,
    rideType: 'Movera',
    price: 75,
    paymentMethod: 'Cash',
    rideId: 'trp_1',
  );

  group('P5-R2 search: /rides/{id}/nearby', () {
    test('live: a search does not ask for cars around the pickup', () async {
      final r = recording(live);
      final realtime = MockRideRealtime(assignAfter: const Duration(days: 1));
      final controller = FindingDriverController(
        realtime: realtime,
        ride: RideSession()..rideId = 'trp_1',
        api: r.api,
        store: FindingDriverRepository(),
      );
      controller.start(
        snapshot: ride().copyWith(status: RideStatus.findingDriver),
        onTick: (_) {},
        onMatched: () {},
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(r.calls.where((c) => c.endsWith('/nearby')), isEmpty);
      expect(controller.nearby, isEmpty);
      controller.dispose();
      realtime.dispose();
    });
  });

  group('P5-R3 Safety: /safety/*', () {
    test(
      'live: loading and changing Safety sends nothing and says why',
      () async {
        final r = recording(live);
        final store = SafetyStore(api: r.api);
        await store.load();
        expect(store.served, isFalse);
        await expectLater(
          store.patchRideCheck(false),
          throwsA(
            isA<SafetyException>()
                .having((e) => e.code, 'code', 'NOT_SERVED')
                .having(
                  (e) => e.message,
                  'message',
                  L10n.current.safetyNotOnServer,
                ),
          ),
        );
        await expectLater(
          store.createContact(name: 'Anna', phone: '+46701234567'),
          throwsA(isA<SafetyException>()),
        );
        expect(store.contacts, isEmpty);
        expect(r.calls, isEmpty);
      },
    );

    test('demo: the in-process Safety server is still asked', () async {
      final r = recording(demo);
      final store = SafetyStore(api: r.api);
      expect(store.served, isTrue);
      await store.load();
      expect(r.calls, contains('GET /api/v1/safety/preferences'));
    });

    testWidgets('live: the Safety screen says settings cannot be saved yet', (
      tester,
    ) async {
      final r = recording(live);
      final ctl = SafetyController(session: SafetyStore(api: r.api));
      await tester.pumpWidget(MaterialApp(home: SafetyHub(controller: ctl)));
      await tester.pumpAndSettle();
      expect(find.text(L10n.current.safetyNotOnServer), findsOneWidget);
      expect(r.calls, isEmpty);
    });

    testWidgets('demo: no such notice', (tester) async {
      final r = recording(demo);
      final ctl = SafetyController(session: SafetyStore(api: r.api));
      await tester.pumpWidget(MaterialApp(home: SafetyHub(controller: ctl)));
      await tester.pumpAndSettle();
      expect(find.text(L10n.current.safetyNotOnServer), findsNothing);
    });
  });

  group('P5-R4 Change route: /rides/{id}/route-quote', () {
    test('live: pricing a new route sends nothing and says it is not '
        'available', () async {
      final r = recording(live);
      final changes = RouteChangeController(api: r.api, geocoding: _Geo());
      expect(changes.available, isFalse);
      await expectLater(
        changes.preview(
          ride: ride(),
          destinationAddress: 'Odenplan',
          destinationPoint: const GeoPoint(59.3429, 18.0496),
        ),
        throwsA(
          isA<RouteChangeException>().having(
            (e) => e.failure,
            'failure',
            RouteChangeFailure.unavailable,
          ),
        ),
      );
      expect(r.calls, isEmpty);
      expect(
        const RouteChangeException(RouteChangeFailure.unavailable).message,
        L10n.current.routeChangeUnavailable,
      );
    });

    testWidgets('live: Change route tells the rider instead of opening an '
        'editor that cannot save', (tester) async {
      final r = recording(live);
      RideSnapshot? result = ride();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async => result = await openRouteChange(
                  context,
                  ride: ride(),
                  entry: RouteChangeEntry.destination,
                  pickupLocked: true,
                  controller: RouteChangeController(
                    api: r.api,
                    geocoding: _Geo(),
                  ),
                ),
                child: const Text('change'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('change'));
      await tester.pumpAndSettle();
      expect(result, isNull);
      expect(find.text(L10n.current.changeRoute), findsNothing);
      expect(find.text(L10n.current.routeChangeUnavailable), findsOneWidget);
      expect(r.calls, isEmpty);
    });

    test('demo: route changes stay on', () {
      final r = recording(demo);
      expect(
        RouteChangeController(api: r.api, geocoding: _Geo()).available,
        isTrue,
      );
    });
  });

  group('P5-R5 account security: /account/security', () {
    test('live: not asked; the screens show their unavailable state', () async {
      final r = recording(live);
      final repo = AccountSecurityRepository(api: r.api);
      await expectLater(repo.load(), throwsA(isA<AccountSecurityNotServed>()));
      await expectLater(
        repo.signOutOtherDevices(),
        throwsA(isA<AccountSecurityNotServed>()),
      );
      expect(r.calls, isEmpty);
    });

    test('demo: still asked', () async {
      final r = recording(demo);
      await expectLater(
        AccountSecurityRepository(api: r.api).load(),
        throwsA(anything),
      );
      expect(r.calls, ['GET /api/v1/account/security']);
    });
  });

  group('P5-R7 ride report: /rides/{id}/disputes', () {
    test('live: not sent, and the reason is not "your connection"', () async {
      final r = recording(live);
      await expectLater(
        RideDisputeRepository(
          api: r.api,
        ).submit(rideId: 'trp_1', reason: 'charged_more'),
        throwsA(isA<RideDisputeNotServed>()),
      );
      expect(r.calls, isEmpty);
    });

    test('demo: still sent', () async {
      final r = recording(demo);
      await expectLater(
        RideDisputeRepository(
          api: r.api,
        ).submit(rideId: 'trp_1', reason: 'charged_more'),
        throwsA(anything),
      );
      expect(r.calls, ['POST /api/v1/rides/trp_1/disputes']);
    });

    testWidgets('live: Help says the report was not sent and why', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final r = recording(live);
      await tester.pumpWidget(
        MaterialApp(
          home: SupportChat(
            contact: const SupportContact(email: ''),
            ride: SupportRide(
              id: 'ondemand-trp_1',
              title: 'To Odenplan',
              when: DateTime(2026, 10, 26, 22, 32),
              price: 54,
              image: 'assets/images/rides/movera.webp',
            ),
            issue: 'I was charged more than expected',
            send: ({required rideId, required reason, detail}) =>
                RideDisputeRepository(
                  api: r.api,
                ).submit(rideId: rideId, reason: reason, detail: detail),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('support-message-send')));
      await tester.pumpAndSettle();
      expect(find.text(L10n.current.reportNotOnServer), findsOneWidget);
      expect(find.text(L10n.current.supportSendFailed), findsNothing);
      expect(find.byKey(const ValueKey('support-message-sent')), findsNothing);
      expect(r.calls, isEmpty);
    });
  });
}

class _Geo implements GeocodingRepository {
  @override
  Future<PlaceResult?> forward(String query) async => null;

  @override
  Future<String?> reverse(GeoPoint point) async => null;
}
