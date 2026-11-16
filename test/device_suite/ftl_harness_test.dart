import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/staging/mask_text.dart';
import '../../integration_test/staging/trip_rules.dart';

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
}
