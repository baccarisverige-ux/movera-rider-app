/// v0.18.155 (contract.json#driverProfile.setting): in core/config so the
/// rider config reader can set it without importing a feature (rider guard).
/// The zone's switches, `RiderAppConfig.driverProfile { on, reviews }`
/// (defaults: on, reviews off). Set from the served rider document.
class DriverProfileSettings {
  const DriverProfileSettings({required this.on, required this.reviews});
  static const defaults = DriverProfileSettings(on: true, reviews: false);
  static DriverProfileSettings current = defaults;
  final bool on;
  final bool reviews;

  static DriverProfileSettings fromJson(Object? json) {
    if (json is! Map) return defaults;
    return DriverProfileSettings(
      on: json['on'] is bool ? json['on'] as bool : defaults.on,
      reviews: json['reviews'] is bool
          ? json['reviews'] as bool
          : defaults.reviews,
    );
  }
}
