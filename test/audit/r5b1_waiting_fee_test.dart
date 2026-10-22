import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_fee_counter.dart';

void main() {
  test('rider-r5-1: the waiting fee counts by the second, as the driver '
      'charges it', () {
    final since = DateTime.utc(2026, 10, 20, 9);
    final state = WaitingFeeState.at(
      since: since,
      now: since.add(const Duration(minutes: 6, seconds: 50)),
      freeWaitMin: 5,
      perMin: const Money(500, 'SEK'),
    );
    // 110 s at 5 kr/min = 9,17 kr.
    expect(state.fee, const Money(917, 'SEK'));
  });
}
