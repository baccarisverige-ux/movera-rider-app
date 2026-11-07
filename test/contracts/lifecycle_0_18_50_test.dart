import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/contracts/trip_status.dart';
import 'package:movera_rider/core/contracts/trip_transitions.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/core/contracts/cancel_fee.dart';
import 'package:movera_rider/features/reservations/domain/scheduled_ride_rules.dart';
import 'package:movera_rider/features/reservations/presentation/reservation_format.dart';

/// Contract v0.18.50 §72 (L5, L12) and v0.18.49 §71 (Q10) in the rider's
/// mirrors of the contract.
void main() {
  final contract =
      jsonDecode(File('contracts/contract.json').readAsStringSync()) as Map;

  test('L12: system release of a queued live trip goes back to searching', () {
    expect(
      TripStateMachine.apply(
        TripStatus.accepted,
        'release',
        TripActor.system,
        kind: TripKind.live,
      ),
      TripStatus.searching,
    );
    // The booked-ride release is unchanged (back to the list).
    expect(
      TripStateMachine.apply(
        TripStatus.accepted,
        'release',
        TripActor.system,
        kind: TripKind.scheduled,
      ),
      TripStatus.requested,
    );
  });

  test('L5: the driver rates a trip the rider ended early', () {
    expect(
      TripRatingRules.allows(
        TripActor.driver,
        TripStatus.cancelledByRider,
        endedBy: 'end_early',
      ),
      isTrue,
    );
    expect(
      TripRatingRules.allows(
        TripActor.driver,
        TripStatus.cancelledByRider,
        endedBy: 'cancel',
      ),
      isFalse,
    );
  });

  test('Q10: the 5 free minutes after booking are the contract value', () {
    final booked = (contract['afterTestRules'] as Map)['bookedCancel'] as Map;
    expect(
      ScheduledRideRules.cancelGraceAfterBooking.inMinutes,
      booked['graceAfterBookingMin'],
    );
  });

  test('Q10: the booking line keeps the contract freeRule and adds the '
      'category cancel cost (no grace line: owner question)', () {
    final line = ReservationFormat.freeRule(
      60,
      rule: const FeeRule(freeMin: 120, type: FeeType.fixed, value: 5000),
      fare: const Money(42000),
    );
    expect(
      line,
      startsWith('Free change and cancel more than 1 hour before pickup. '),
    );
    expect(line, isNot(contains('5 min after booking')));
    expect(line, contains('Cancelling less than 120 min before pickup costs'));
    expect(
      ReservationFormat.freeRule(60),
      'Free change and cancel more than 1 hour before pickup',
    );
  });

  test('v0.18.51 L6: admin reassign of a held booked ride goes back to '
      'the list; a live one searches again', () {
    expect(
      TripStateMachine.apply(
        TripStatus.accepted,
        'reassign',
        TripActor.admin,
        kind: TripKind.scheduled,
      ),
      TripStatus.requested,
    );
    expect(
      TripStateMachine.apply(
        TripStatus.accepted,
        'reassign',
        TripActor.admin,
        kind: TripKind.live,
      ),
      TripStatus.searching,
    );
  });
}
