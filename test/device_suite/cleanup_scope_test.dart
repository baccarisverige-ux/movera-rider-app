import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/staging/cleanup_scope.dart';

/// F1 (supervisor 2026-11-13): the device suite's clean-up closes only the
/// trips the run made, never one the shared test rider had before the run.
void main() {
  group('cleanupScope', () {
    test('only the recorded bookings when no answer was lost', () {
      final s = cleanupScope(
        booked: ['trp_a', 'trp_b'],
        answerLost: false,
        openBefore: {'trp_old'},
        openNow: {'trp_old', 'trp_a', 'trp_x'},
      );
      expect(s.ids, ['trp_a', 'trp_b']);
      expect(s.unknown, isFalse);
    });

    test('a lost answer adds only trips new since the snapshot', () {
      final s = cleanupScope(
        booked: ['trp_a'],
        answerLost: true,
        openBefore: {'trp_old', 'trp_booked_before'},
        openNow: {'trp_old', 'trp_booked_before', 'trp_a', 'trp_new'},
      );
      expect(s.ids, ['trp_a', 'trp_new']);
      expect(s.ids, isNot(contains('trp_old')));
      expect(s.ids, isNot(contains('trp_booked_before')));
      expect(s.unknown, isFalse);
    });

    test('unknown snapshot or unreadable now: nothing added, flagged', () {
      for (final (before, now) in [
        (null, <String>{'trp_old', 'trp_new'}),
        (<String>{'trp_old'}, null),
        (null, null),
      ]) {
        final s = cleanupScope(
          booked: const [],
          answerLost: true,
          openBefore: before,
          openNow: now,
        );
        expect(s.ids, isEmpty);
        expect(s.unknown, isTrue);
      }
    });

    test('no duplicates, empty ids dropped', () {
      final s = cleanupScope(
        booked: ['trp_a', '', 'trp_a'],
        answerLost: true,
        openBefore: <String>{},
        openNow: {'trp_a'},
      );
      expect(s.ids, ['trp_a']);
    });
  });

  test('bookedTripIdOf takes only a real tripId', () {
    expect(bookedTripIdOf({'tripId': 'trp_1'}), 'trp_1');
    expect(bookedTripIdOf({'tripId': ''}), isNull);
    expect(bookedTripIdOf({'id': 'trp_1'}), isNull);
    expect(bookedTripIdOf(null), isNull);
    expect(bookedTripIdOf('trp_1'), isNull);
  });

  test('bookingAnswerLost: no answer, error, 5xx, 2xx without id', () {
    expect(bookingAnswerLost(status: null), isTrue);
    expect(bookingAnswerLost(status: 0), isTrue);
    expect(bookingAnswerLost(status: 201, error: 'ClientException'), isTrue);
    expect(bookingAnswerLost(status: 503), isTrue);
    expect(bookingAnswerLost(status: 201, answer: {'x': 1}), isTrue);
    expect(bookingAnswerLost(status: 201, answer: {'tripId': 't'}), isFalse);
    // A 4xx is a clear refusal: nothing was made.
    expect(bookingAnswerLost(status: 409), isFalse);
    expect(bookingAnswerLost(status: 400), isFalse);
  });
}
