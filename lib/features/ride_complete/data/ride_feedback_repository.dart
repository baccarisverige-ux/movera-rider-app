import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/features/ride_complete/domain/tip_refused.dart';

export 'package:movera_rider/features/ride_complete/domain/tip_refused.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/features/ratings/domain/rating_tags.dart';

/// Sends optional post-trip feedback through the same API transport as the ride.
/// An acknowledgement is required before the completion screen closes.
class RideFeedbackRepository {
  RideFeedbackRepository({ApiClient? api})
    : _api = api ?? AppScope.instance.api;

  final ApiClient _api;

  Future<void> submit({
    required String rideId,
    double? rating,
    int? tipMinor,
    String tipCurrency = Money.defaultCurrency,
    List<String> tags = const <String>[],
    String? comment,
    String tipMethod = 'cash',
    required String idempotencyKey,
  }) async {
    if (rideId.trim().isEmpty) throw ArgumentError.value(rideId, 'rideId');
    // Contract v0.9.0: tags from contract.json#ratings.tags.aboutDriver, once
    // each, and a comment of at most 2000 characters.
    if (tags.any((tag) => !RatingTags.isAllowed(tag)) ||
        tags.toSet().length != tags.length ||
        tags.length > RatingTags.maxPerRating) {
      throw ArgumentError.value(tags, 'tags');
    }
    final note = comment?.trim();
    if (note != null && note.length > RatingTags.commentMaxLength) {
      throw ArgumentError.value(comment, 'comment');
    }
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
      // Contract v0.18.10 (`finish.tips`, owner G8 item 1): the tip goes on
      // `POST /trips/{tripId}/tip`. Cash only today: the rider gives it in
      // the driver's hand; all of it goes to the driver.
      final tip = tipMinor == null
          ? null
          : {'amountMinor': tipMinor, 'currency': tipCurrency};
      // The rating and the tip go separately (the server answers each on
      // its own), so a refused tip never loses the rating.
      if (rating != null) {
        await _api.post(
          _api.tripPath(rideId, 'rating'),
          body: {
            'stars': rating.round(),
            if (tags.isNotEmpty) 'tags': tags,
            if (note != null && note.isNotEmpty) 'comment': note,
          },
          idempotencyKey: idempotencyKey,
        );
      }
      if (tip != null) {
        try {
          await _api.post(
            _api.tripPath(rideId, 'tip'),
            body: {'amount': tip, 'method': tipMethod},
            idempotencyKey: '$idempotencyKey-tip',
          );
        } on ApiError catch (error) {
          if (rating == null) rethrow;
          throw TipRefusedAfterRating(error);
        }
      }
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
}
