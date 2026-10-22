import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/scheduled_rides/application/scheduled_rides_controller.dart';
import 'package:movera_rider/features/scheduled_rides/application/stockholm_schedule.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('scheduled session owns route time note payment and ids', () {
    final session = ScheduledRideSession();
    session.captureRoute(
      pickup: 'Current location',
      dropoff: 'Stockholm Central Station',
      stops: ['Odenplan'],
    );
    final when = DateTime.utc(2099, 9, 23, 10, 30);
    session.captureSchedule(
      when,
      timezone: 'Europe/Stockholm',
    );
    session.captureNote('Ring the bell');
    session.capturePayment('Cash');
    session.captureRideType('economy');
    expect(session.pickup, 'Current location');
    expect(session.dropoff, 'Stockholm Central Station');
    expect(session.stops, ['Odenplan']);
    expect(session.scheduledAt, when);
    expect(session.timezone, 'Europe/Stockholm');
    expect(session.note, 'Ring the bell');
    expect(session.paymentMethod, 'Cash');
    expect(session.rideType, 'economy');
    expect(
      session.quoteId,
      isNull,
      reason: 'a scheduled quote id must come from a real quote source',
    );
    expect(session.bookingId, isNull);
  });

  test('captureSchedule clamps a past pickup to Stockholm now+30', () {
    final session = ScheduledRideSession();
    session.captureSchedule(DateTime.utc(2026, 9, 13, 10, 30));
    expect(session.scheduledAt, isNotNull);
    expect(StockholmSchedule.isLegalPickup(session.scheduledAt!), isTrue);
    expect(session.scheduledAt, StockholmSchedule.minimumPickup());
  });

  test('confirm writes booking id onto the session', () async {
    final session = ScheduledRideSession();
    session.captureRoute(
      pickup: 'Current location',
      dropoff: 'Stockholm Central Station',
      stops: const [],
    );
    session.captureSchedule(DateTime.utc(2099, 9, 23, 10, 30));
    session.capturePayment('Wallet');
    session.captureRideType('economy', quoteId: 'q_sched_1');
    final id = await session.confirm(book: () async => 'b_sched_1');
    expect(id, 'b_sched_1');
    expect(session.bookingId, 'b_sched_1');
    expect(session.quoteId, 'q_sched_1');
    expect(session.submissionStatus, 'confirmed');
  });
}
