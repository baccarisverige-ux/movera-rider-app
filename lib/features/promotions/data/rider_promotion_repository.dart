import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/features/promotions/domain/rider_promotion.dart';

/// Reads the rider's active promotion from `/api/v1/rider/promotions/active`.
class RiderPromotionRepository {
  RiderPromotionRepository(this._api);

  final ApiClient _api;

  /// The active promotion, or null when the server has none. Throws when
  /// the lookup fails (rider-r5-22: that is not "no promotion").
  Future<RiderPromotion?> fetchActive() async {
    final body = await _api.get('/api/v1/rider/promotions/active');
    return RiderPromotion.fromJson(body['promotion']);
  }
}
