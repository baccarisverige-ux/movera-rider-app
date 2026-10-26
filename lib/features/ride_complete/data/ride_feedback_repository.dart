import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/core/logging/app_log.dart';

/// Sends optional post-trip feedback through the same API transport as the ride.
/// An acknowledgement is required before the completion screen closes.
class RideFeedbackRepository {
  RideFeedbackRepository({ApiClient? api}) : _api = api ?? AppScope.instance.api;

  final ApiClient _api;

  Future<void> submit({
    required String rideId,
    double? rating,
    int? tipMinor,
    String tipCurrency = Money.defaultCurrency,
    required String idempotencyKey,
  }) async {
    if (rideId.trim().isEmpty) throw ArgumentError.value(rideId, 'rideId');
    if (rating == null && tipMinor == null) return;
    // Q38 / X20: whole stars only, 1 to 5.
    if (rating != null &&
        (rating < 1 || rating > 5 || rating != rating.roundToDouble())) {
      throw ArgumentError.value(rating, 'rating');
    }
    if (tipMinor != null && (tipMinor <= 0 || tipMinor > 999900)) {
      throw ArgumentError.value(tipMinor, 'tipMinor');
    }
    if (_api.contractWire) {
      // Contract `POST /trips/{tripId}/rating` (`RatingRequest`): whole
      // stars; the server answers 201 with the `Rating`. Tips are not
      // available on the server yet (`tips_not_available`), so a tip is
      // never sent with the rating and a tip alone is refused here.
      if (rating == null) {
        throw StateError('Tips are not available yet.');
      }
      if (tipMinor != null) {
        AppLog.warning('ride.feedback.tip_not_sent', extra: {'rideId': rideId});
      }
      await _api.post(
        _api.tripPath(rideId, 'rating'),
        body: {'stars': rating.round()},
        idempotencyKey: idempotencyKey,
      );
      return;
    }
    final response = await _api.post(
      '/api/v1/rides/${Uri.encodeComponent(rideId)}/feedback',
      body: {
        // Contract `Rating.stars`: a whole number, sent as an integer.
        if (rating != null) 'rating': rating.round(),
        if (tipMinor != null) 'tipMinor': tipMinor,
        // Q5: the trip's currency (the server refuses any other).
        if (tipMinor != null) 'currency': tipCurrency,
      },
      idempotencyKey: idempotencyKey,
    );
    if (response['code'] != 'OK' || response['status'] != 'accepted') {
      throw StateError('Ride feedback was not accepted.');
    }
  }

  /// The rider closed the finished-trip screen without rating: contract
  /// `RatingRequest {skip: true}` (ratingStatus → skipped), so no device
  /// shows that screen again. The demo's mock has no skip.
  Future<void> skip({
    required String rideId,
    required String idempotencyKey,
  }) async {
    if (rideId.trim().isEmpty || !_api.contractWire) return;
    await _api.post(
      _api.tripPath(rideId, 'rating'),
      body: {'skip': true},
      idempotencyKey: idempotencyKey,
    );
  }
}
