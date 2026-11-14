import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/config/live_data_only.dart';
import 'package:movera_rider/core/contracts/cancel_fee.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/core/contracts/wire_time.dart';
import 'package:movera_rider/core/realtime/ride_realtime.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_for_driver.dart';
import 'package:movera_rider/features/finding_driver/presentation/cancel_ride_sheet.dart';
import 'package:movera_rider/features/reservations/data/api_reservation_repository.dart';
import 'package:movera_rider/features/reservations/domain/scheduled_ride_rules.dart';
import 'package:movera_rider/features/reservations/presentation/reservation_edit_sheets.dart';
import 'package:movera_rider/features/reservations/presentation/reservation_format.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/matched_driver.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:movera_rider/shared/design_system/movera_icon_button.dart';
import 'package:movera_rider/shared/formatters/money.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A trip feed the test drives: each event carries the payload it is given.
class _Feed implements RideRealtime {
  final _events = StreamController<RideRealtimeEvent>.broadcast();
  int _sequence = 0;

  void add(RideStatus status, {Map<String, Object?> payload = const {}}) {
    _sequence += 1;
    _events.add(
      RideRealtimeEvent(
        tripId: 'm22-r2',
        status: status,
        sequence: _sequence,
        version: _sequence,
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

const _nb = ' ';

Map<String, Object?> _money(int minor, String c) => {
  'amountMinor': minor,
  'currency': c,
};

/// The trip's own terms: a 50 kr cancel fee from the first minute, so the
/// phone's own calculator would say "Cancelling now costs 50 kr.".
Map<String, Object?> _terms() => {
  'currency': 'SEK',
  'freeWaitMin': 5,
  'waitPerMin': _money(500, 'SEK'),
  'noShowAfterMin': 5,
  'noShowFee': _money(6500, 'SEK'),
  'cancelRule': {'freeMin': 0, 'type': 'fixed', 'value': 5000},
  'cancelAfterArrivedIsNoShow': true,
  'maxPickupMoveMeters': 200,
};

/// BQ-M22 rider round 2 (supervisor Rules audits/impact/m24-apps-supervisor.md
/// MF1 / MF2 / S4 / S5 / S6; owner rule: the apps never work money out,
/// absent server number → no amount).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RideSnapshotStore.epoch = 0;
    L10n.use('en');
    AppScope.instance.ride
      ..rideId = null
      ..suppressRestore = false
      ..authoritativeVersion = null
      ..authoritativeUpdatedAt = null
      ..restoreFromBackend(RideStatus.idle);
  });
  tearDown(() {
    LiveDataOnly.on = false;
    L10n.use('en');
  });

  /// Opens the live cancel sheet after [payload] arrived; returns its note.
  Future<String?> sheetNote(
    WidgetTester tester,
    Map<String, Object?> payload,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    final feed = _Feed();
    addTearDown(feed.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: WaitingForDriver(
          pickupAddress: 'Vasagatan 1',
          destinationAddress: 'Kungsgatan 2',
          pickupPosition: const LatLng(59.3293, 18.0686),
          destinationPosition: const LatLng(59.3326, 18.0649),
          rideType: 'Movera',
          categoryId: 'economy',
          price: 300,
          currency: 'SEK',
          paymentMethod: 'Cash',
          rideId: 'm22-r2',
          driver: const MatchedDriver(id: 'd1', firstName: 'Anna'),
          realtime: feed,
          persistRideSnapshot: false,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final accepted = DateTime.now().toUtc().subtract(
      const Duration(minutes: 10),
    );
    feed.add(
      RideStatus.driverArriving,
      payload: {acceptedAtKey: WireTime.format(accepted), ...payload},
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final close = tester.widget<MoveraIconButton>(
      find.ancestor(
        of: find.byIcon(Icons.close_rounded).first,
        matching: find.byType(MoveraIconButton),
      ),
    );
    close.onPressed();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(CancelRideSheet), findsOneWidget);
    final note = tester.widget<CancelRideSheet>(find.byType(CancelRideSheet));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
    return note.feeNote;
  }

  group('MF1 live sheet: no preview on a real build → no amount', () {
    testWidgets('trip terms only: no worked-out fee, no "free" line', (
      tester,
    ) async {
      LiveDataOnly.on = true;
      final note = await sheetNote(tester, {termsKey: _terms()});
      expect(note ?? '', isNot(contains('kr')), reason: 'no amount');
      expect(note ?? '', isNot(contains('costs')));
      expect(note ?? '', isNot(contains('free')), reason: 'no made-up free');
      expect(note, isNot(L10n.current.noFeeToCancel));
      expect(note, L10n.current.cancelFeeNotShown);
    });

    testWidgets('demo build keeps the calculator (unchanged)', (tester) async {
      LiveDataOnly.on = false;
      final note = await sheetNote(tester, {termsKey: _terms()});
      expect(
        note,
        L10n.current.cancelCostsNow(formatMoney(const Money(5000, 'SEK'))),
      );
    });
  });

  group('S4 wiring: _cancelFeeNote reads the preview from the trip', () {
    testWidgets('the preview wins over the terms (45,00 kr, not 50)', (
      tester,
    ) async {
      LiveDataOnly.on = true;
      final note = await sheetNote(tester, {
        termsKey: _terms(),
        wholeProjectionKey: true,
        cancelPreviewKey: {'feeNow': _money(4500, 'SEK'), 'kind': 'cancel'},
      });
      expect(note, 'Cancelling now costs 45,00${_nb}kr.');
    });

    testWidgets('a preview in another currency is never shown', (tester) async {
      LiveDataOnly.on = true;
      final note = await sheetNote(tester, {
        termsKey: _terms(),
        wholeProjectionKey: true,
        cancelPreviewKey: {'feeNow': _money(800, 'EUR'), 'kind': 'cancel'},
      });
      expect(note ?? '', isNot(contains('€')));
      expect(note ?? '', isNot(contains('kr')));
      expect(note ?? '', isNot(contains('costs')));
      expect(note, L10n.current.cancelFeeNotShown);
    });
  });

  Map<String, dynamic> trip(
    Map<String, Object?>? preview, {
    String currency = 'SEK',
  }) => {
    'tripId': 'B1',
    'kind': 'scheduled',
    'status': 'accepted',
    'scheduledAt': '2026-11-14T14:00:00Z',
    'createdAt': '2026-11-14T08:00:00Z',
    'fare': _money(30000, currency),
    'categoryId': 'economy',
    'pickup': {'address': 'A', 'lat': 59.3, 'lng': 18.0},
    'dropoff': {'address': 'B', 'lat': 59.4, 'lng': 18.1},
    'cancelPreview': ?preview,
  };
  const rule = FeeRule(freeMin: 60, type: FeeType.fixed, value: 4000);
  final late = DateTime.utc(2026, 11, 14, 13, 30);

  group('MF1 booked ride: no preview on a real build → no amount', () {
    test('no worked-out fee and no free line', () {
      LiveDataOnly.on = true;
      final ride = ApiReservationRepository.reservationOfTrip(trip(null));
      final terms = ScheduledRideRules.defaults.cancelTermsFor(
        ride,
        late,
        categoryRule: rule,
      );
      expect(terms.fee, isNull, reason: 'never a phone-worked fee');
      expect(terms.freeForNow, isFalse);
      expect(ReservationFormat.cancelTermsBody(terms), isNull);
      final shown = [
        ReservationFormat.cancelTermsTitle(terms),
        ReservationFormat.cancellationSummary(terms),
        ReservationFormat.cancelRuleOf(terms),
      ];
      for (final text in shown) {
        expect(text, L10n.current.cancelFeeNotShown);
        expect(text, isNot(contains('kr')), reason: text);
        expect(text.toLowerCase(), isNot(contains('free')), reason: text);
        expect(text, isNot(L10n.current.noFeeToCancel));
      }
    });

    test('demo build keeps the calculator', () {
      LiveDataOnly.on = false;
      final ride = ApiReservationRepository.reservationOfTrip(trip(null));
      final terms = ScheduledRideRules.defaults.cancelTermsFor(
        ride,
        late,
        categoryRule: rule,
      );
      expect(terms.fee, const Money(4000, 'SEK'));
    });
  });

  group('MF2 booked sheet text keeps the decimals', () {
    test('SEK fee now: "45,00 kr"', () {
      final ride = ApiReservationRepository.reservationOfTrip(
        trip({
          'feeNow': _money(0, 'SEK'),
          'kind': 'cancel',
          'freeUntil': '2026-11-14T13:00:00Z',
          'feeAfterFree': _money(4500, 'SEK'),
          'kindAfterFree': 'cancel',
        }),
      );
      final terms = ScheduledRideRules.defaults.cancelTermsFor(ride, late);
      expect(
        ReservationFormat.cancelTermsTitle(terms),
        'Cancellation fee: 45,00${_nb}kr',
      );
      expect(
        ReservationFormat.cancelTermsBody(terms),
        contains('45,00${_nb}kr'),
      );
      expect(
        ReservationFormat.cancellationSummary(terms),
        contains('45,00${_nb}kr'),
      );
      final early = ScheduledRideRules.defaults.cancelTermsFor(
        ride,
        DateTime.utc(2026, 11, 14, 12),
      );
      expect(
        ReservationFormat.cancelTermsBody(early),
        contains('45,00${_nb}kr'),
      );
      // The free end comes from the server (one hour before pickup).
      expect(ReservationFormat.cancelTermsBody(early), contains('1 h'));
    });

    test('TND fee now: "5.000 DT"; sv keeps "45,00 kr"', () {
      final tnd = ApiReservationRepository.reservationOfTrip(
        trip({
          'feeNow': _money(5000, 'TND'),
          'kind': 'cancel',
        }, currency: 'TND'),
      );
      final terms = ScheduledRideRules.defaults.cancelTermsFor(tnd, late);
      expect(
        ReservationFormat.cancelTermsTitle(terms),
        'Cancellation fee: 5.000${_nb}DT',
      );
      L10n.use('sv');
      final sek = ApiReservationRepository.reservationOfTrip(
        trip({'feeNow': _money(4500, 'SEK'), 'kind': 'cancel'}),
      );
      expect(
        ReservationFormat.cancelTermsTitle(
          ScheduledRideRules.defaults.cancelTermsFor(sek, late),
        ),
        contains('45,00${_nb}kr'),
      );
    });
  });

  testWidgets('MF2 / MF1: the booked cancel sheet note shows the text', (
    tester,
  ) async {
    final ride = ApiReservationRepository.reservationOfTrip(
      trip({'feeNow': _money(4500, 'SEK'), 'kind': 'cancel'}),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReservationCancelTermsNote(
            terms: ScheduledRideRules.defaults.cancelTermsFor(ride, late),
          ),
        ),
      ),
    );
    expect(find.text('Cancellation fee: 45,00${_nb}kr'), findsOneWidget);
    expect(find.text('Cancelling now costs 45,00${_nb}kr.'), findsOneWidget);
    LiveDataOnly.on = true;
    final unknown = ScheduledRideRules.defaults.cancelTermsFor(
      ApiReservationRepository.reservationOfTrip(trip(null)),
      late,
      categoryRule: rule,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ReservationCancelTermsNote(terms: unknown)),
      ),
    );
    expect(find.byKey(const Key('reservation-cancel-unknown')), findsOneWidget);
    expect(find.text(L10n.current.cancelFeeNotShown), findsOneWidget);
    expect(find.textContaining('kr'), findsNothing);
    expect(find.textContaining('ree'), findsNothing, reason: 'no free line');
  });

  test('S6: a fee now with no step never names "now" as the free end', () {
    final ride = ApiReservationRepository.reservationOfTrip(
      trip({'feeNow': _money(4500, 'SEK'), 'kind': 'cancel'}),
    );
    final terms = ScheduledRideRules.defaults.cancelTermsFor(ride, late);
    final body = ReservationFormat.cancelTermsBody(terms);
    final summary = ReservationFormat.cancellationSummary(terms);
    for (final text in [body!, summary]) {
      expect(text, isNot(contains('ended at')), reason: text);
      expect(text, isNot(contains('13:30')), reason: text);
      expect(text, contains('45,00${_nb}kr'));
    }
  });

  test('S5: no break inside an amount; thousands grouped', () {
    expect(formatMoneyFull(const Money(4000, 'SEK')), '40,00${_nb}kr');
    expect(
      formatMoneyFull(const Money(100000, 'SEK')),
      '1${_nb}000,00${_nb}kr',
    );
    expect(formatMoneyFull(const Money(800, 'EUR')), '8,00$_nb€');
    expect(formatMoneyFull(const Money(5000, 'TND')), '5.000${_nb}DT');
    expect(
      formatMoneyFull(const Money(1250000, 'TND')),
      '1${_nb}250.000${_nb}DT',
    );
  });
}
