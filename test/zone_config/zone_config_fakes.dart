import 'package:movera_rider/core/config/rider_app_config.dart';

/// A config source whose zone documents a test edits: [overrides] by zone
/// id are laid over that zone's built-in seed, as Admin would publish them.
class EditedZoneConfigs implements RiderConfigRepository {
  EditedZoneConfigs([this.overrides = const {}]);

  final Map<String, Map<String, Object?>> overrides;

  /// Zone ids asked for, in order.
  final List<String> asked = [];

  @override
  Future<RiderAppConfig> current() async => SeedRiderConfigRepository.seed;

  @override
  Future<RiderAppConfig> forZone(String zoneId) async {
    asked.add(zoneId);
    final seed = SeedRiderConfigRepository.seedFor(zoneId);
    final edits = overrides[zoneId];
    if (edits == null) return seed;
    return RiderAppConfig.fromJson({
      'version': seed.version,
      'zoneId': seed.zoneId,
      'currency': seed.currency,
      'country': seed.country,
      ...edits,
    }, fallback: seed)!;
  }
}

/// `{amountMinor, currency}` on the wire.
Map<String, Object> wireMoney(int minor, String currency) => {
  'amountMinor': minor,
  'currency': currency,
};
