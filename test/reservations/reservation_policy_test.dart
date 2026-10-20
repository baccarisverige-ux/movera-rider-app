import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/reservations/data/reservation_policy_catalog.dart';

void main() {
  test('unpublished policy does not invent fees or windows', () {
    final policy = ReservationPolicyCatalog.current;
    expect(policy.version, 'unpublished.v1');
    expect(policy.freeCancellationMinutes, isNull);
    expect(policy.cancellationFee, isNull);
    expect(policy.includedWaitMinutes, isNull);
    expect(policy.minimumAdvanceBookingMinutes, isNull);
    final blob = [
      policy.pricingDisclaimer,
      policy.assignmentDisclaimer,
      policy.waitingSummary,
      policy.cancellationSummary,
      policy.pricingSummary,
      ...policy.sections.map((s) => '${s.title} ${s.body}'),
    ].join(' ');
    expect(blob.toLowerCase(), isNot(contains('uber')));
    expect(blob.toLowerCase(), isNot(contains('prototype')));
    expect(blob.toLowerCase(), isNot(contains('placeholder')));
    expect(blob, isNot(contains('160')));
    expect(blob, isNot(contains('240')));
    expect(blob.toLowerCase(), isNot(contains('we\'ll send your driver by')));
  });
}
