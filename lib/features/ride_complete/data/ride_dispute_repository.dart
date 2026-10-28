import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/mutation_attempt.dart';
import 'package:movera_rider/features/support/application/support_ticket_repository.dart';

export 'package:movera_rider/features/ride_complete/domain/ride_dispute_not_served.dart';

/// Backend seam for disputing a completed ride receipt.
///
/// The Rider submits the rider's reason but never invents a dispute result.
class RideDisputeRepository {
  RideDisputeRepository({ApiClient? api}) : _api = api ?? AppScope.instance.api;

  final ApiClient _api;
  final MutationAttempt _mutation = MutationAttempt('ride-dispute');

  Future<void> submit({
    required String rideId,
    required String reason,
    String? detail,
  }) async {
    final id = rideId.trim();
    final normalizedReason = reason.trim();
    final normalizedDetail = detail?.trim();

    if (id.isEmpty || normalizedReason.isEmpty) {
      throw ArgumentError('rideId and reason are required.');
    }
    // Contract v0.9.0 (owner, 2026-10-27): a ride dispute is a support
    // ticket (`POST /support/tickets`, category ride_dispute); Movera's
    // answer comes back on the ticket.
    if (_api.contractWire) {
      final text = (normalizedDetail == null || normalizedDetail.isEmpty)
          ? normalizedReason
          : normalizedDetail;
      await SupportTicketRepository(api: _api).open(
        tripId: id,
        category: 'ride_dispute',
        subject: SupportTicketRepository.subjectOf(
          text,
          fallback: normalizedReason,
        ),
        text: text,
      );
      return;
    }

    final intent = '$id|$normalizedReason|${normalizedDetail ?? ''}';
    await _api.post(
      '/api/v1/rides/$id/disputes',
      body: {
        'reason': normalizedReason,
        if (normalizedDetail != null && normalizedDetail.isNotEmpty)
          'detail': normalizedDetail,
      },
      idempotencyKey: _mutation.keyFor(intent),
    );
    _mutation.succeeded(intent);
  }
}
