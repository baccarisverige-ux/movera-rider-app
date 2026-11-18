import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/staging/mask_text.dart';
import '../../integration_test/staging/trip_rules.dart';
import 'mask_probes.g.dart';

/// FTL-H1, FTL-H3, FTL-H4 (Rules audits/impact/firebase-trip-run-2026-11-16.md
/// rows 1, 4 and 5): the plain rules of the rider device run's trip steps
/// and the masking of the recorded app error texts. Made-up values only.
void main() {
  group('FTL-H1 stop short of the arrive distance', () {
    test('default terms: 150 m (100 m + 50, at least 150)', () {
      expect(autoArriveMetersOf(null), 100);
      expect(stopShortMeters(null), 150);
      expect(stopShortMeters({'terms': <String, Object?>{}}), 150);
    });

    test('the trip terms win; never under 150 m', () {
      expect(
        stopShortMeters({
          'terms': {'autoArriveMeters': 300},
        }),
        350,
      );
      expect(
        stopShortMeters({
          'terms': {'autoArriveMeters': 30},
        }),
        150,
      );
    });

    test('run 43900906554: the old stop (~39 m) was inside 100 m', () {
      // trip_book.dart before: north -30 / east -25 = ~39 m short.
      expect(39 < autoArriveMetersOf(null), isTrue);
      expect(stopShortMeters(null) > autoArriveMetersOf(null), isTrue);
    });

    test('SWITCH status: same, or a server auto-arrive on the way', () {
      expect(switchStatusKept('driver_to_pickup', 'driver_to_pickup'), isTrue);
      expect(switchStatusKept('in_trip', 'in_trip'), isTrue);
      expect(switchStatusKept('driver_to_pickup', 'arrived'), isTrue);
      expect(switchStatusKept('accepted', 'arrived'), isTrue);
      expect(switchStatusKept('in_trip', 'completed'), isFalse);
      expect(switchStatusKept('driver_to_pickup', 'cancelled'), isFalse);
      expect(switchStatusKept(null, 'arrived'), isFalse);
    });

    test('SWITCH trip kept: the arrived sheet only with a server arrived', () {
      bool kept(bool trip, bool sheet, String? status) => tripKept(
        tripOnTop: trip,
        arrivedSheetOnTop: sheet,
        statusAfter: status,
      );
      expect(kept(true, false, 'driver_to_pickup'), isTrue);
      expect(kept(false, true, 'arrived'), isTrue);
      // A lost trip screen never passes.
      expect(kept(false, false, 'arrived'), isFalse);
      expect(kept(false, false, 'driver_to_pickup'), isFalse);
      expect(kept(false, true, 'driver_to_pickup'), isFalse);
      expect(kept(false, true, 'in_trip'), isFalse);
      expect(kept(false, true, null), isFalse);
    });

    test('arrive only when not arrived; 409 after an auto-arrive is fine', () {
      expect(arriveNeeded('driver_to_pickup'), isTrue);
      expect(arriveNeeded('arrived'), isFalse);
      expect(arriveAnswerOk(200, 'arrived'), isTrue);
      expect(arriveAnswerOk(409, 'arrived'), isTrue);
      expect(arriveAnswerOk(409, 'driver_to_pickup'), isFalse);
      expect(arriveAnswerOk(500, 'arrived'), isFalse);
    });
  });

  group('FTL-H3 ride check answered', () {
    test('server check with the rider answer', () {
      expect(
        rideCheckAnswered(
          serverRideCheck: {
            'answers': {'rider': 'ok'},
          },
          postsSinceCard: const [],
        ),
        isTrue,
      );
    });

    test("the app's own check: server rideCheck null, POST 2xx counts", () {
      expect(
        rideCheckAnswered(serverRideCheck: null, postsSinceCard: [201]),
        isTrue,
      );
      expect(
        rideCheckAnswered(
          serverRideCheck: null,
          postsSinceCard: ['ClientException', 409],
        ),
        isFalse,
      );
      expect(
        rideCheckAnswered(serverRideCheck: null, postsSinceCard: const []),
        isFalse,
      );
    });
  });

  group('FTL-H4 masked error text', () {
    const phone = '+46000097531'; // made up
    const code = '9876'; // made up

    test('the run values in any spelling', () {
      final out = maskText(
        'rejected +46000097531 / +46 00 009 75 31 / 000-009 75 31 code 9876',
        known: const [phone, code],
      );
      expect(out, isNot(contains('97531')));
      expect(out.replaceAll(RegExp(r'\D'), ''), isNot(contains('9876')));
      expect(out, contains(masked));
    });

    test('any phone-shaped number, tokens and named values', () {
      final out = maskText(
        'call 0000012345 or +33 0 00 11 22 33; Bearer abc.def-123; '
        'eyJhbGciOi.eyJzdWIiOi.sig_1; {"token": "s3cr3t", password=hunter2}; '
        'id 123456789012',
      );
      for (final leak in [
        '0000012345',
        '00 11 22 33',
        'abc.def-123',
        'eyJhbGciOi',
        's3cr3t',
        'hunter2',
        '123456789012',
      ]) {
        expect(out, isNot(contains(leak)), reason: leak);
      }
    });

    // Supervisor review 2026-11-16: spellings the first version let through.
    test('phone numbers without a lead, with thin spaces, in brackets', () {
      for (final leak in [
        '20 123 456', // Tunisian national (8 digits, no trunk 0)
        '20123456',
        '+216 20 123 456',
        '216 20 123 456',
        '06 12 34 56 78', // French national
        '06.12.34.56.78',
        '+33 6 12 34 56 78',
        '+33 6 12 34 56 78', // no-break spaces
        '+33 6 12 34 56 78',
        '+33 (0)6 12 34 56 78',
        '46 70 123 45 67', // +46 without the plus
        '70 123 45 67',
        '+46 (0) 70 123 45 67',
        '(070) 123-45-67',
        '070-123 45 67',
        '0046701234567',
      ]) {
        final out = maskText('rider $leak not found');
        expect(out, 'rider $masked not found', reason: leak);
        expect(maskText('user_$leak'), isNot(contains(leak)), reason: leak);
      }
    });

    test('tokens and passwords under any name', () {
      final out = maskText(
        'access_token=tokA1 refresh_token: tokB2 {"idToken":"tokC3"} '
        'client_secret=secD4 newPassword=pwE5 pwd=pwF6 x-api-key: keyG7 '
        'Authorization: Basic dXNlcjpwYXNzH8 sessionToken=tokI9 '
        'sess 0a1B2c3D4e5F6g7H8i9J0k1L2m3N4o5P6q7R the code was 482913 '
        'mail someone@example.com',
      );
      for (final leak in [
        'tokA1',
        'tokB2',
        'tokC3',
        'secD4',
        'pwE5',
        'pwF6',
        'keyG7',
        'dXNlcjpwYXNzH8',
        'tokI9',
        '0a1B2c3D4e5F6g7H8i9J0k1L2m3N4o5P6q7R',
        '482913',
        'someone@example.com',
      ]) {
        expect(out, isNot(contains(leak)), reason: leak);
      }
    });

    test('a known value of 8 digits does not break the masking', () {
      final out = maskText(
        'code 12345678 / 1234 5678',
        known: const ['12345678'],
      );
      expect(out.replaceAll(RegExp(r'\D'), ''), isEmpty);
    });

    test('keeps a stack frame and a size', () {
      const text =
          '#12     _RideCompletedState.build (package:movera_rider/x.dart:1080:33) '
          'Size(1080.0, 2400.0) overflowed by 12.5 pixels';
      expect(maskText(text), text);
    });

    test('keeps times, source positions and plain text', () {
      const text =
          "'package:flutter/src/widgets/framework.dart': Failed assertion: "
          "line 5108 pos 12: '_lifecycleState' at 07:58:01, 3 pixels";
      expect(maskText(text), text);
    });

    test('exceptionText: type, library, masked message, first frames', () {
      final stack = StackTrace.fromString(
        '#0      a (package:x/a.dart:1:1)\n'
        '#1      b (package:x/b.dart:2:2)\n'
        '#2      c (package:x/c.dart:3:3)\n'
        '#3      d (package:x/d.dart:4:4)\n',
      );
      final text = exceptionText(
        StateError('no trip for +46000097531'),
        library: 'widgets library',
        stack: stack,
        known: const [phone],
      );
      expect(
        text,
        startsWith('StateError (widgets library): Bad state: no trip for '),
      );
      expect(text, isNot(contains('97531')));
      expect(text, contains('package:x/c.dart:3:3'));
      expect(text, isNot(contains('package:x/d.dart')));
    });

    test('exceptionText cuts a long message', () {
      final text = exceptionText(Exception('x' * 1000), maxChars: 50);
      expect(text.length, lessThan(120));
      expect(text, endsWith('...'));
    });
  });

  // FTL MF-1 (post-merge read 2026-11-16): one table for maskText and
  // tool/testlab_summary.py mask_generic: tool/tests/mask_probes.json (the
  // 76 probe lines, the builder's own extra lines, the lines that must
  // stay readable), here as mask_probes.g.dart; the tool's unit test
  // fails when the two differ. Made-up values only.
  group('FTL MF-1 shared probe table', () {
    test('the table is whole', () {
      expect(probeLines, 76);
      expect(maskProbes.length, greaterThanOrEqualTo(probeLines));
      expect(keepProbes.length, greaterThanOrEqualTo(19));
      for (final (text, gone, out) in maskProbes) {
        expect(gone, isNotEmpty, reason: text);
        expect(out, isNotEmpty, reason: text);
      }
    });

    test('every probe line is masked, with the same output as the tool', () {
      for (final (text, gone, expected) in maskProbes) {
        final out = maskText(text);
        for (final leak in gone) {
          expect(out, isNot(contains(leak)), reason: text);
        }
        expect(out, expected, reason: text);
      }
    });

    test('what a diagnosis needs stays', () {
      for (final text in keepProbes) {
        expect(maskText(text), text);
      }
    });

    test('a known number with slashes or spaced dashes', () {
      for (final spelling in [
        '000/097 531',
        '000 / 097 / 531',
        '000 - 097 - 531',
      ]) {
        final out = maskText('x $spelling y', known: const ['+46000097531']);
        expect(out.replaceAll(RegExp(r'\D'), ''), isEmpty, reason: spelling);
      }
    });

    test('exceptionText: a bare code in a sign-in error is masked', () {
      final text = exceptionText(_OtpProblem('482913'), library: 'x');
      expect(text, isNot(contains('482913')));
      expect(text, startsWith('_OtpProblem (x): '));
      // Not a sign-in error: a plain number stays.
      expect(exceptionText(StateError('line 5108')), contains('5108'));
    });
  });
}

class _OtpProblem implements Exception {
  _OtpProblem(this.value);
  final String value;
  @override
  String toString() => value;
}
