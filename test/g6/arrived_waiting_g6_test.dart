import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/auth/token_store.dart';
import 'package:movera_rider/core/legal/rider_legal.dart';
import 'package:movera_rider/core/realtime/realtime_gate.dart';
import 'package:movera_rider/core/realtime/ride_realtime.dart';
import 'package:movera_rider/features/active_ride/application/trip_pin.dart';
import 'package:movera_rider/features/active_ride/presentation/driver_arrived_sheet.dart';
import 'package:movera_rider/features/active_ride/presentation/trip_pin_card.dart';
import 'package:movera_rider/features/driver_arriving/application/driver_tracking_controller.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/matched_driver.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// Driver group 6 "Arrived and waiting" (contract v0.18.8) in the rider
/// app: the trip PIN, the Terms with the zone's live waiting rules
/// (`?zoneId=`) and the one-off waiting alerts (no sound).

const _env = AppEnv(
  flavor: AppFlavor.staging,
  apiBaseUrl: 'https://api.test.movera.invalid',
);

http.Response _json(int status, Object? body) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

class _Feed implements RideRealtime {
  final _events = StreamController<RideRealtimeEvent>.broadcast();
  int _sequence = 0;

  void add(RideStatus status, {Map<String, Object?> payload = const {}}) {
    _sequence += 1;
    _events.add(
      RideRealtimeEvent(
        tripId: 'g6-trip',
        status: status,
        sequence: _sequence,
        version: _sequence,
        kind: RealtimeKind.tripProjection,
        driver: const MatchedDriver(id: 'd1', firstName: 'Anna'),
        payload: payload,
      ),
    );
  }

  @override
  bool get supportsRiderSignals => false;
  @override
  Stream<RideRealtimeEvent> subscribe(String rideId) => _events.stream;
  @override
  Future<void> reconnectAndResync(String rideId) async {}
  @override
  Future<void> sendSignal({
    required String rideId,
    required RideRealtimeSignal signal,
    String? message,
  }) async {}
  @override
  void unsubscribe() {}
  @override
  void cancelRide() {}
  @override
  void researchAfterDriverCancel() {}
  @override
  void dispose() => unawaited(_events.close());
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

(DriverTrackingController, _Feed) _tracking() {
  final feed = _Feed();
  final tracking = DriverTrackingController(
    realtime: feed,
    pickupLat: 59.33,
    pickupLng: 18.06,
    persistRideSnapshot: false,
  );
  addTearDown(() {
    tracking.dispose();
    feed.dispose();
  });
  tracking.start(rideId: 'g6-trip');
  return (tracking, feed);
}

Widget _app(Widget child, {String locale = 'en'}) {
  L10n.use(locale);
  return MaterialApp(
    locale: Locale(locale),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  tearDown(() => L10n.use('en'));

  group('trip PIN', () {
    test('shows from accept while the driver is on the way and waiting, '
        'hidden once the driver entered it', () async {
      final (tracking, feed) = _tracking();
      const pin = {
        pinRequiredKey: true,
        pickupPinKey: '0427',
        pinVerifiedKey: false,
      };
      feed.add(RideStatus.driverAssigned, payload: pin);
      await _flush();
      expect(tracking.showPin, isTrue);
      expect(tracking.pickupPin, '0427');

      feed.add(RideStatus.driverWaiting, payload: pin);
      await _flush();
      expect(tracking.showPin, isTrue);

      feed.add(
        RideStatus.driverWaiting,
        payload: {...pin, pinVerifiedKey: true},
      );
      await _flush();
      expect(tracking.showPin, isFalse);
    });

    test('no PIN when the trip does not need one', () async {
      final (tracking, feed) = _tracking();
      feed.add(RideStatus.driverArriving, payload: {pinRequiredKey: false});
      await _flush();
      expect(tracking.showPin, isFalse);
    });

    test('not shown once the trip started', () async {
      final (tracking, feed) = _tracking();
      feed.add(
        RideStatus.tripStarted,
        payload: {pinRequiredKey: true, pickupPinKey: '1111'},
      );
      await _flush();
      expect(tracking.showPin, isFalse);
    });

    test('a malformed PIN is ignored', () async {
      final (tracking, feed) = _tracking();
      feed.add(
        RideStatus.driverArriving,
        payload: {pinRequiredKey: true, pickupPinKey: '12a4'},
      );
      await _flush();
      expect(tracking.pickupPin, isNull);
      expect(tracking.showPin, isFalse);
      tracking.setFetchedPin('5678');
      expect(tracking.showPin, isTrue);
    });

    test('GET /trips/{id}/pin returns the PinCode pin; 404 = none', () async {
      final requests = <http.Request>[];
      var status = 200;
      final tokens = MemoryTokenStore();
      await tokens.save(access: 'a', refresh: 'r');
      final api = ApiClient(
        env: _env,
        tokens: tokens,
        client: MockClient((request) async {
          requests.add(request);
          return status == 200
              ? _json(200, {
                  'tripId': 'T1',
                  'pin': '0042',
                  'expiresAt': '2026-11-01T12:00:00Z',
                })
              : _json(404, {
                  'code': 'not_found',
                  'message': 'x',
                  'reason': 'pin_not_required',
                });
        }),
      );
      expect(await fetchTripPin(api, 'T1'), '0042');
      expect(requests.single.url.path, '/api/v1/trips/T1/pin');
      expect(requests.single.method, 'GET');
      status = 404;
      expect(await fetchTripPin(api, 'T1'), isNull);
    });

    for (final (locale, title) in [
      ('en', 'Tell your driver this code'),
      ('sv', 'Säg den här koden till föraren'),
      ('fr', 'Donnez ce code à votre chauffeur'),
    ]) {
      testWidgets('PIN card big and clear ($locale)', (tester) async {
        await tester.pumpWidget(
          _app(const TripPinCard(pin: '0427'), locale: locale),
        );
        await tester.pumpAndSettle();
        expect(find.text(title), findsOneWidget);
        expect(find.text('0 4 2 7'), findsOneWidget);
        final digits = tester.widget<Text>(find.text('0 4 2 7'));
        expect(digits.style!.fontSize, greaterThanOrEqualTo(32));
      });
    }

    testWidgets('arrived sheet shows the PIN only when given', (tester) async {
      await tester.pumpWidget(_app(const DriverArrivedSheet(pin: '9031')));
      await tester.pumpAndSettle();
      expect(find.byType(TripPinCard), findsOneWidget);
      expect(find.text('9 0 3 1'), findsOneWidget);

      await tester.pumpWidget(_app(const DriverArrivedSheet()));
      await tester.pumpAndSettle();
      expect(find.byType(TripPinCard), findsNothing);
    });
  });

  group('waiting alerts (no sound)', () {
    test('each kind once per arrival', () async {
      final (tracking, feed) = _tracking();
      final paid = {
        waitingAlertsKey: [
          {'kind': alertPaidWaitingStarted, 'at': '2026-11-01T10:05:00Z'},
        ],
      };
      feed.add(RideStatus.driverWaiting, payload: paid);
      await _flush();
      expect(tracking.takeNewAlerts(), [alertPaidWaitingStarted]);

      feed.add(RideStatus.driverWaiting, payload: paid);
      await _flush();
      expect(tracking.takeNewAlerts(), isEmpty);

      feed.add(
        RideStatus.driverWaiting,
        payload: {
          waitingAlertsKey: [
            {'kind': alertPaidWaitingStarted, 'at': '2026-11-01T10:05:00Z'},
            {'kind': alertNoShowPossible, 'at': '2026-11-01T10:05:00Z'},
            {'kind': 'unknown_kind', 'at': '2026-11-01T10:05:00Z'},
          ],
        },
      );
      await _flush();
      expect(tracking.takeNewAlerts(), [alertNoShowPossible]);
      expect(tracking.takeNewAlerts(), isEmpty);
    });

    test('no alert outside the waiting status', () async {
      final (tracking, feed) = _tracking();
      feed.add(
        RideStatus.tripStarted,
        payload: {
          waitingAlertsKey: [
            {'kind': alertPaidWaitingStarted, 'at': '2026-11-01T10:05:00Z'},
          ],
        },
      );
      await _flush();
      expect(tracking.takeNewAlerts(), isEmpty);
    });

    testWidgets('texts sv/fr/en are time only (no amounts)', (tester) async {
      final seen = <String, List<String>>{};
      for (final locale in ['en', 'sv', 'fr']) {
        await tester.pumpWidget(
          _app(
            Builder(
              builder: (context) {
                seen[locale] = [
                  waitingAlertText(context.l10n, alertPaidWaitingStarted),
                  waitingAlertText(context.l10n, alertNoShowPossible),
                ];
                return const SizedBox();
              },
            ),
            locale: locale,
          ),
        );
        await tester.pumpAndSettle();
      }
      expect(seen['en'], [
        'The free waiting is over',
        'The driver may now end the ride as a no-show',
      ]);
      expect(seen['sv']![0], 'Den fria väntetiden är slut');
      expect(seen['fr']![0], 'L’attente gratuite est terminée');
      for (final texts in seen.values) {
        for (final text in texts) {
          expect(text, isNot(matches(RegExp(r'\d|kr|€'))));
        }
      }
    });
  });

  group('Terms with the zone', () {
    Future<List<Uri>> load(Future<String?> Function(String)? zoneId) async {
      final urls = <Uri>[];
      final tokens = MemoryTokenStore();
      final legal = RiderLegalController(
        api: ApiClient(
          env: _env,
          tokens: tokens,
          client: MockClient((request) async {
            urls.add(request.url);
            return _json(404, {'code': 'not_found', 'message': 'x'});
          }),
        ),
        store: MemoryLegalStore(),
        country: () async => 'SE',
        zoneId: zoneId,
      );
      addTearDown(legal.dispose);
      await legal.load();
      return urls;
    }

    test('asks GET /legal/{country}?zoneId= for 3.5 live numbers', () async {
      final urls = await load((country) async => 'Z001');
      expect(urls.single.path, '/api/v1/legal/SE');
      expect(urls.single.queryParameters, {'zoneId': 'Z001'});
    });

    test('no zone (or failing lookup) = plain terms', () async {
      expect((await load(null)).single.query, isEmpty);
      expect((await load((_) async => null)).single.query, isEmpty);
      expect(
        (await load((_) async => throw StateError('no fix'))).single.query,
        isEmpty,
      );
    });
  });
}
