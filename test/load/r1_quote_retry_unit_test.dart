import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/ride_selection/application/quote_retry.dart';

/// R1 (owner 2026-11-13 "Yes, with screenshots"): the exact numbers the
/// owner approved. After a busy round Select ride asks again after 2 s,
/// doubling up to 30 s, ±20 %, never sooner than Retry-After (itself at
/// most 30 s), at most 5 retries, then "Try again"; an answer resets it.
class _Fixed implements math.Random {
  _Fixed(this.value);

  /// What nextDouble returns: 0 → -20 %, 0.5 → exact, ~1 → +20 %.
  final double value;

  @override
  double nextDouble() => value;

  @override
  int nextInt(int max) => 0;

  @override
  bool nextBool() => false;
}

void main() {
  const second = Duration(seconds: 1);

  List<Duration?> waits(QuoteRetry retry, int rounds, {Duration? after}) => [
    for (var i = 0; i < rounds; i++)
      (retry..record(busy: true, retryAfter: after)).nextWait,
  ];

  test('steps 2, 4, 8, 16, 30 s (the cap), then it gives up: exactly 5 '
      'retries', () {
    final retry = QuoteRetry(random: _Fixed(0.5));
    expect(waits(retry, 5), [
      second * 2,
      second * 4,
      second * 8,
      second * 16,
      second * 30,
    ]);
    expect(retry.gaveUp, isFalse, reason: '5 retries so far');
    retry.record(busy: true);
    expect(retry.gaveUp, isTrue, reason: 'the 6th busy round: no more');
    expect(retry.nextWait, isNull);
    expect(retry.failures, 6);
  });

  test('±20 %: each wait stays within 0.8 × and 1.2 × its step', () {
    final steps = [2, 4, 8, 16, 30];
    final low = waits(QuoteRetry(random: _Fixed(0)), 5);
    final high = waits(QuoteRetry(random: _Fixed(0.999999)), 5);
    for (var i = 0; i < 5; i++) {
      final step = steps[i] * 1000;
      expect(low[i]!.inMilliseconds, step * 8 ~/ 10);
      expect(high[i]!.inMilliseconds, lessThanOrEqualTo(step * 12 ~/ 10));
      expect(high[i]!.inMilliseconds, greaterThan(step * 119 ~/ 100));
    }
  });

  test('never sooner than Retry-After (the floor)', () {
    final retry = QuoteRetry(random: _Fixed(0));
    retry.record(busy: true, retryAfter: second * 10);
    expect(retry.nextWait, second * 10);
    retry.record(busy: true, retryAfter: second);
    expect(retry.nextWait, Duration(milliseconds: 3200), reason: '4 s - 20 %');
  });

  test('Retry-After is capped at 30 s (a "Retry-After: 3600" waits 30 s)', () {
    final retry = QuoteRetry(random: _Fixed(0.5));
    retry.record(busy: true, retryAfter: const Duration(seconds: 3600));
    expect(retry.nextWait, second * 30);
  });

  test('an answered round resets it', () {
    final retry = QuoteRetry(random: _Fixed(0.5));
    waits(retry, 3);
    retry.record(busy: false);
    expect(retry.failures, 0);
    expect(retry.nextWait, isNull);
    expect(retry.gaveUp, isFalse);
    retry.record(busy: true);
    expect(retry.nextWait, second * 2);
  });
}
