import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/core/contracts/cancel_fee.dart';
import 'package:movera_rider/core/contracts/cancel_preview.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/core/contracts/ride_status.dart';
import 'package:movera_rider/core/realtime/ride_realtime.dart';
import 'package:movera_rider/features/active_ride/presentation/cancel_preview_note.dart';
import 'package:movera_rider/features/finding_driver/domain/cancellation_reason.dart';
import 'package:movera_rider/features/finding_driver/presentation/cancel_ride_sheet.dart';
import 'package:movera_rider/features/reservations/data/api_reservation_repository.dart';
import 'package:movera_rider/features/reservations/domain/scheduled_ride_rules.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// BQ-M22 rider part (contract v0.18.92 priceDisplay.cancelPreview; owner
/// rule: the apps never work money out): the cancel sheet shows the
/// server's `cancelPreview.feeNow`, and from `freeUntil` on `feeAfterFree`
/// with the `kindAfterFree` label (a clock compare, no maths). The rider
/// contract copy is older than 0.18.92 (not merged yet): the field is read
/// as optional; absent → today's behaviour (the server's own kept rules).
void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() => L10n.use('en'));

  Map<String, Object?> money(int minor, String c) => {
    'amountMinor': minor,
    'currency': c,
  };
  final at = DateTime.utc(2026, 11, 14, 12);

  group('CancelPreview.fromWire', () {
    test('SEK step: free now, 50,00 kr from freeUntil', () {
      final p = CancelPreview.fromWire({
        'feeNow': money(0, 'SEK'),
        'kind': 'cancel',
        'freeUntil': '2026-11-14T12:03:00Z',
        'feeAfterFree': money(5000, 'SEK'),
        'kindAfterFree': 'cancel',
      })!;
      expect(p.feeNow, const Money(0, 'SEK'));
      expect(p.freeUntil, DateTime.utc(2026, 11, 14, 12, 3));
      final before = p.at(at);
      expect(before.fee, const Money(0, 'SEK'));
      expect(before.kind, CancelPreviewKind.cancel);
      final after = p.at(DateTime.utc(2026, 11, 14, 12, 3));
      expect(after.fee, const Money(5000, 'SEK'));
      expect(after.kind, CancelPreviewKind.cancel);
    });

    test('EUR arrived: cancel before freeUntil, no-show fee after', () {
      final p = CancelPreview.fromWire({
        'feeNow': money(0, 'EUR'),
        'kind': 'cancel',
        'freeUntil': '2026-11-14T12:05:00Z',
        'feeAfterFree': money(800, 'EUR'),
        'kindAfterFree': 'no_show',
      })!;
      final after = p.at(DateTime.utc(2026, 11, 14, 12, 6));
      expect(after.fee, const Money(800, 'EUR'));
      expect(after.kind, CancelPreviewKind.noShow);
    });

    test('TND fee now, no step; absent or broken → null', () {
      final p = CancelPreview.fromWire({
        'feeNow': money(2500, 'TND'),
        'kind': 'cancel',
      })!;
      expect(p.at(at).fee, const Money(2500, 'TND'));
      expect(p.freeUntil, isNull);
      expect(CancelPreview.fromWire(null), isNull);
      expect(CancelPreview.fromWire({'kind': 'cancel'}), isNull);
      expect(
        CancelPreview.fromWire({
          'feeNow': {'amountMinor': 'x', 'currency': 'SEK'},
          'kind': 'cancel',
        }),
        isNull,
      );
      // An older server without kindAfterFree keeps the kind label.
      final old = CancelPreview.fromWire({
        'feeNow': money(0, 'SEK'),
        'kind': 'cancel',
        'freeUntil': '2026-11-14T12:03:00Z',
        'feeAfterFree': money(5000, 'SEK'),
      })!;
      expect(
        old.at(DateTime.utc(2026, 11, 14, 13)).kind,
        CancelPreviewKind.cancel,
      );
    });

    test('a realtime event carries it (projection cancelPreview)', () {
      final event = RideRealtimeEvent(
        rideId: 'T1',
        status: RideStatus.driverArriving,
        sequence: 1,
        payload: {
          cancelPreviewKey: {'feeNow': money(5000, 'SEK'), 'kind': 'cancel'},
        },
      );
      expect(event.cancelPreview!.feeNow, const Money(5000, 'SEK'));
      expect(
        RideRealtimeEvent(
          rideId: 'T1',
          status: RideStatus.driverArriving,
          sequence: 1,
        ).cancelPreview,
        isNull,
      );
    });
  });

  group('cancel sheet note from the preview (no maths)', () {
    test('free now with a step: minutes left to freeUntil', () {
      final p = CancelPreview.fromWire({
        'feeNow': money(0, 'SEK'),
        'kind': 'cancel',
        'freeUntil': '2026-11-14T12:03:00Z',
        'feeAfterFree': money(5000, 'SEK'),
        'kindAfterFree': 'cancel',
      })!;
      final now = cancelPreviewNote(p, DateTime.utc(2026, 11, 14, 12, 0, 30));
      expect(now.charged, isFalse);
      expect(now.text, 'Cancelling is free for 3 more minutes.');
      expect(
        cancelPreviewNote(p, DateTime.utc(2026, 11, 14, 12, 2, 30)).text,
        'Cancelling is free for less than a minute more.',
      );
      final later = cancelPreviewNote(p, DateTime.utc(2026, 11, 14, 12, 3));
      expect(later.charged, isTrue);
      expect(later.text, 'Cancelling now costs 50,00 kr.');
    });

    test('no-show label from kindAfterFree (EUR), TND keeps 3 decimals', () {
      final p = CancelPreview.fromWire({
        'feeNow': money(0, 'EUR'),
        'kind': 'cancel',
        'freeUntil': '2026-11-14T12:05:00Z',
        'feeAfterFree': money(800, 'EUR'),
        'kindAfterFree': 'no_show',
      })!;
      final after = cancelPreviewNote(p, DateTime.utc(2026, 11, 14, 12, 5));
      expect(after.charged, isTrue);
      expect(after.text, contains('8,00'));
      expect(after.text, contains('no-show'));
      final tnd = cancelPreviewNote(
        CancelPreview.fromWire({
          'feeNow': money(2500, 'TND'),
          'kind': 'cancel',
        })!,
        at,
      );
      expect(tnd.text, contains('2.500 DT'));
    });

    test('free with no step: no fee', () {
      final p = CancelPreview.fromWire({
        'feeNow': money(0, 'SEK'),
        'kind': 'cancel',
      })!;
      expect(cancelPreviewNote(p, at).text, 'No fee to cancel this ride.');
    });

    test('sv / fr texts', () {
      final p = CancelPreview.fromWire({
        'feeNow': money(0, 'SEK'),
        'kind': 'cancel',
        'freeUntil': '2026-11-14T12:05:00Z',
        'feeAfterFree': money(4000, 'SEK'),
        'kindAfterFree': 'no_show',
      })!;
      L10n.use('sv');
      final sv = cancelPreviewNote(p, DateTime.utc(2026, 11, 14, 12, 6)).text;
      expect(sv, contains('40,00 kr'));
      L10n.use('fr');
      final fr = cancelPreviewNote(p, DateTime.utc(2026, 11, 14, 12, 6)).text;
      expect(fr, contains('40,00'));
      expect(sv, isNot(fr));
    });
  });

  group('booked ride: the reservation cancel terms come from the preview', () {
    Map<String, dynamic> trip(Map<String, Object?>? preview) => {
      'tripId': 'B1',
      'kind': 'scheduled',
      'status': 'accepted',
      'scheduledAt': '2026-11-14T14:00:00Z',
      'createdAt': '2026-11-14T08:00:00Z',
      'fare': money(30000, 'SEK'),
      'categoryId': 'economy',
      'pickup': {'address': 'A', 'lat': 59.3, 'lng': 18.0},
      'dropoff': {'address': 'B', 'lat': 59.4, 'lng': 18.1},
      'cancelPreview': ?preview,
    };
    // A rule that would give another number: the preview wins.
    const rule = FeeRule(freeMin: 60, type: FeeType.fixed, value: 99);

    test('before freeUntil: free for now, then the server feeAfterFree', () {
      final ride = ApiReservationRepository.reservationOfTrip(
        trip({
          'feeNow': money(0, 'SEK'),
          'kind': 'cancel',
          'freeUntil': '2026-11-14T13:00:00Z',
          'feeAfterFree': money(4500, 'SEK'),
          'kindAfterFree': 'cancel',
        }),
      );
      expect(ride.cancelPreview, isNotNull);
      final terms = ScheduledRideRules.defaults.cancelTermsFor(
        ride,
        DateTime.utc(2026, 11, 14, 12),
        categoryRule: rule,
      );
      expect(terms.fee, isNull);
      expect(terms.freeForNow, isTrue);
      expect(terms.lateFee, const Money(4500, 'SEK'));
      expect(terms.freeUntil, DateTime.utc(2026, 11, 14, 13));
      final late = ScheduledRideRules.defaults.cancelTermsFor(
        ride,
        DateTime.utc(2026, 11, 14, 13, 30),
        categoryRule: rule,
      );
      expect(late.fee, const Money(4500, 'SEK'));
    });

    test('a fee now with no step (TND)', () {
      final ride = ApiReservationRepository.reservationOfTrip({
        ...trip({'feeNow': money(3000, 'TND'), 'kind': 'cancel'}),
        'fare': money(20000, 'TND'),
      });
      final terms = ScheduledRideRules.defaults.cancelTermsFor(
        ride,
        DateTime.utc(2026, 11, 14, 13, 30),
        categoryRule: rule,
      );
      expect(terms.fee, const Money(3000, 'TND'));
      expect(terms.freeForNow, isFalse);
    });

    test('absent (older server): today\'s terms from the kept rule', () {
      final ride = ApiReservationRepository.reservationOfTrip(trip(null));
      expect(ride.cancelPreview, isNull);
      final terms = ScheduledRideRules.defaults.cancelTermsFor(
        ride,
        DateTime.utc(2026, 11, 14, 13, 30),
        categoryRule: const FeeRule(
          freeMin: 60,
          type: FeeType.fixed,
          value: 40,
        ),
      );
      expect(terms.fee?.isPositive, isTrue, reason: 'the kept rule, as today');
    });
  });

  for (final lang in const ['en', 'sv']) {
    testWidgets('$lang: the cancel sheet shows the server preview', (
      tester,
    ) async {
      final shot = Platform.environment['MOVERA_SHOT_DIR'];
      if (shot != null) await tester.runAsync(_loadFonts);
      L10n.use(lang);
      tester.view.physicalSize = const Size(390 * 2, 844 * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final p = CancelPreview.fromWire({
        'feeNow': money(0, 'SEK'),
        'kind': 'cancel',
        'freeUntil': '2026-11-14T12:05:00Z',
        'feeAfterFree': money(4000, 'SEK'),
        'kindAfterFree': 'no_show',
      })!;
      final note = cancelPreviewNote(p, DateTime.utc(2026, 11, 14, 12, 6));
      final boundary = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: RepaintBoundary(
            key: boundary,
            child: Scaffold(
              backgroundColor: const Color(0xFF8A8F94),
              body: Align(
                alignment: Alignment.bottomCenter,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                  ),
                  child: CancelRideSheet(
                    takingLonger: false,
                    phase: CancelPhase.matched,
                    feeNote: note.text,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(note.text), findsOneWidget);
      expect(note.text, contains('40,00 kr'));
      if (shot != null) {
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await render.toImage(pixelRatio: 2);
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          File('$shot/rider-cancel-sheet-$lang.png')
            ..createSync(recursive: true)
            ..writeAsBytesSync(png!.buffer.asUint8List());
        });
      }
    });
  }
}

/// Screenshots only: real glyphs for the Poppins families the sheet asks for.
Future<void> _loadFonts() async {
  const dir = '/usr/share/fonts/truetype/dejavu';
  Future<ByteData> bytes(String f) async =>
      ByteData.sublistView(File('$dir/$f').readAsBytesSync());
  for (final (family, file) in [
    ('Poppins_regular', 'DejaVuSans.ttf'),
    ('Poppins_500', 'DejaVuSans.ttf'),
    ('Poppins_600', 'DejaVuSans-Bold.ttf'),
    ('Poppins_700', 'DejaVuSans-Bold.ttf'),
    ('Roboto', 'DejaVuSans.ttf'),
  ]) {
    await (FontLoader(family)..addFont(bytes(file))).load();
  }
}
