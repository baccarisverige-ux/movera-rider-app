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

  test('Q10: the booking line says the category cancel rule, not a free '
      'cancel in the change window', () {
    final line = ReservationFormat.freeRule(
      60,
      rule: const FeeRule(freeMin: 120, type: FeeType.fixed, value: 5000),
      fare: const Money(42000),
    );
    expect(line, isNot(contains('change and cancel')));
    expect(line, contains('Free cancel for 5 min after booking'));
    expect(line, contains('Cancelling less than 120 min before pickup costs'));
  });
}
