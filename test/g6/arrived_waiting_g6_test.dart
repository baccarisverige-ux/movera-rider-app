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
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/features/ride_booking/data/ride_projection.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

Future<void> _flush() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

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
  setUp(() => SharedPreferences.setMockInitialValues({}));

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

    test('a new driver brings a new PIN, shown again until entered; '
        'an end status stops it', () async {
      final (tracking, feed) = _tracking();
      feed.add(
        RideStatus.driverWaiting,
        payload: {
          pinRequiredKey: true,
          pickupPinKey: '1234',
          pinVerifiedKey: true,
        },
      );
      await _flush();
      expect(tracking.showPin, isFalse);
      // Trip changed driver: new PIN in the projection.
      feed.add(
        RideStatus.driverArriving,
        payload: {pinRequiredKey: true, pickupPinKey: '8765'},
      );
      await _flush();
      expect(tracking.pickupPin, '8765');
      expect(tracking.showPin, isTrue);
      feed.add(RideStatus.noShow, payload: {pinRequiredKey: true});
      await _flush();
      expect(tracking.pickupPin, isNull);
      tracking.clearPin();
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
      var reason = 'pin_not_required';
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
                  'reason': reason,
                });
        }),
      );
      expect((await fetchTripPin(api, 'T1')).pin, '0042');
      expect(requests.single.url.path, '/api/v1/trips/T1/pin');
      expect(requests.single.method, 'GET');
      status = 404;
      final none = await fetchTripPin(api, 'T1');
      expect((none.pin, none.over), (null, false));
      reason = 'pin_trip_over';
      final over = await fetchTripPin(api, 'T1');
      expect((over.pin, over.over), (null, true));
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

  group('waiting alerts survive a reopen', () {
    Map<String, Object?> alerts(List<String> kinds, String arrivedAt) => {
      waitingArrivedAtKey: arrivedAt,
      waitingAlertsKey: [
        for (final kind in kinds) {'kind': kind, 'at': arrivedAt},
      ],
    };

    test('a reopened screen does not show the same alert again; '
        'a new arrival does', () async {
      final (first, feed1) = _tracking();
      await _flush();
      feed1.add(
        RideStatus.driverWaiting,
        payload: alerts([alertPaidWaitingStarted], '2026-11-01T10:00:00Z'),
      );
      await _flush();
      expect(first.takeNewAlerts(), [alertPaidWaitingStarted]);

      // App reopened: a new controller, same trip and arrival.
      final (second, feed2) = _tracking();
      feed2.add(
        RideStatus.driverWaiting,
        payload: alerts([
          alertPaidWaitingStarted,
          alertNoShowPossible,
        ], '2026-11-01T10:00:00Z'),
      );
      await _flush();
      expect(second.takeNewAlerts(), [alertNoShowPossible]);

      // Another arrival (new driver) on the same trip.
      final (third, feed3) = _tracking();
      feed3.add(
        RideStatus.driverWaiting,
        payload: alerts([alertPaidWaitingStarted], '2026-11-01T10:30:00Z'),
      );
      await _flush();
      expect(third.takeNewAlerts(), [alertPaidWaitingStarted]);
    });
  });

  group('reversed no-show', () {
    Map<String, dynamic> trip(Map<String, Object?> extra) => {
      'cancellation': {
        'actor': 'driver',
        'reasonCode': 'no_show',
        'at': '2026-11-01T10:10:00Z',
        'fee': {'amountMinor': 6500, 'currency': 'SEK'},
        'feeKind': 'no_show',
        'reversal': {'at': '2026-11-01T11:00:00Z'},
        ...extra,
      },
    };

    test('round 1: feeStatus waived + refundedToWallet = refunded', () {
      final r = RideProjection.noShowReversal(
        trip({
          'feeStatus': 'waived',
          'refundedToWallet': true,
          'refundedAt': '2026-11-01T11:00:00Z',
        }),
      );
      expect(r.reversed, isTrue);
      expect(r.refunded?.amountMinor, 6500);
    });

    test('feeStatus refunded or refundedAt = refunded to wallet', () {
      final a = RideProjection.noShowReversal(trip({'feeStatus': 'refunded'}));
      expect(a.reversed, isTrue);
      expect(a.refunded?.amountMinor, 6500);
      final b = RideProjection.noShowReversal(
        trip({'feeStatus': 'paid', 'refundedAt': '2026-11-01T11:00:00Z'}),
      );
      expect(b.refunded?.amountMinor, 6500);
    });

    test('waived or unknown status = no fee, no refund, no crash', () {
      for (final status in ['waived', 'brand_new_status', 42, null]) {
        final r = RideProjection.noShowReversal(trip({'feeStatus': status}));
        expect(r.reversed, isTrue);
        expect(r.refunded, isNull);
      }
      expect(
        RideProjection.noShowReversal({'cancellation': 'x'}).reversed,
        isFalse,
      );
      final plain = trip({})..['cancellation'].remove('reversal');
      expect(RideProjection.noShowReversal(plain).reversed, isFalse);
    });

    test('kept on the history record across a restart', () {
      final json = {
        'reservationId': 'ondemand-T1',
        'createdAt': '2026-11-01T09:00:00Z',
        'scheduledPickupAt': '2026-11-01T10:00:00Z',
        'pickup': {'label': 'A', 'lat': 59.3, 'lng': 18.0},
        'destination': {'label': 'B', 'lat': 59.4, 'lng': 18.1},
        'categoryId': 'movera',
        'categoryName': 'Movera',
        'price': 100,
        'currency': 'SEK',
        'paymentMethod': 'Wallet',
        'status': 'cancelled',
        'noShowReversed': true,
        'refundedToWallet': {'amountMinor': 6500, 'currency': 'SEK'},
      };
      final parsed = Reservation.tryParse(json)!;
      expect(parsed.noShowReversed, isTrue);
      expect(parsed.refundedToWallet, const Money(6500, 'SEK'));
      final again = Reservation.tryParse(parsed.toJson())!;
      expect(again.noShowReversed, isTrue);
      expect(again.refundedToWallet?.amountMinor, 6500);
    });

    for (final (locale, line, refund) in [
      ('en', 'No-show reversed · no fee', 'Refunded to your wallet X'),
      (
        'sv',
        'Utebliven kund ångrad · ingen avgift',
        'Återbetalt till din plånbok X',
      ),
      (
        'fr',
        'Absence annulée · aucuns frais',
        'Remboursé sur votre portefeuille X',
      ),
    ]) {
      testWidgets('texts ($locale)', (tester) async {
        late String a, b;
        await tester.pumpWidget(
          _app(
            Builder(
              builder: (context) {
                a = context.l10n.noShowReversedNoFee;
                b = context.l10n.refundedToWallet('X');
                return const SizedBox();
              },
            ),
            locale: locale,
          ),
        );
        expect(a, line);
        expect(b, refund);
      });
    }
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
