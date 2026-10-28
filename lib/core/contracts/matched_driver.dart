import 'package:movera_rider/l10n/l10n.dart';
import 'package:movera_rider/shared/formatters/name_format.dart';

/// Driver payload from matching. UI must not invent missing fields.
class MatchedDriver {
  const MatchedDriver({
    required this.id,
    required this.firstName,
    this.rating,
    this.tripCount,
    this.vehicleMake,
    this.vehicleModel,
    this.vehicleColor,
    this.plate,
    this.photoAsset,
    this.vehicleImageAsset,
    this.languages = const [],
    this.yearsOnMovera,
  });

  final String id;
  final String firstName;
  final double? rating;
  final int? tripCount;
  final String? vehicleMake;
  final String? vehicleModel;
  final String? vehicleColor;
  final String? plate;
  final String? photoAsset;
  final String? vehicleImageAsset;
  final List<String> languages;
  final int? yearsOnMovera;

  String get normalizedFirstName => firstName.trim();

  bool get hasFirstName => normalizedFirstName.isNotEmpty;

  String get displayFirstName =>
      hasFirstName ? normalizedFirstName : L10n.current.driver;

  String get initial => initialFromName(normalizedFirstName);

  String get vehicleLabel {
    final parts = [
      if (vehicleColor != null && vehicleColor!.isNotEmpty) vehicleColor,
      if (vehicleMake != null && vehicleMake!.isNotEmpty) vehicleMake,
      if (vehicleModel != null && vehicleModel!.isNotEmpty) vehicleModel,
    ];
    return parts.join(' ');
  }

  String? get ratingLabel {
    final value = rating;
    if (value == null) return null;
    return value.toStringAsFixed(value == value.roundToDouble() ? 1 : 2);
  }

  String? get tripsLabel {
    final count = tripCount;
    if (count == null) return null;
    return '$count trips';
  }

  /// Contract `DriverSummary` (`driverId`, nested `vehicle`), plus the
  /// app-only extras the mock driver pool and the ride snapshot carry.
  Map<String, dynamic> toJson() => {
    'driverId': id,
    'firstName': firstName,
    if (rating != null) 'rating': rating,
    if (tripCount != null) 'tripCount': tripCount,
    'vehicle': {
      if (vehicleMake != null) 'make': vehicleMake,
      if (vehicleModel != null) 'model': vehicleModel,
      if (vehicleColor != null) 'color': vehicleColor,
      if (plate != null) 'plate': plate,
    },
    if (photoAsset != null) 'photoAsset': photoAsset,
    if (vehicleImageAsset != null) 'vehicleImageAsset': vehicleImageAsset,
    if (languages.isNotEmpty) 'languages': languages,
    if (yearsOnMovera != null) 'yearsOnMovera': yearsOnMovera,
  };

  static MatchedDriver? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    // rider-16: contract `DriverSummary` carries `driverId` and a nested
    // `vehicle`; the flat pre-contract keys are still read (old snapshots).
    final id = json['driverId'] as String? ?? json['id'] as String? ?? '';
    final firstName =
        (json['firstName'] as String? ?? json['name'] as String? ?? '').trim();
    if (id.isEmpty || firstName.isEmpty) return null;
    final langs = json['languages'];
    final rawVehicle = json['vehicle'];
    final vehicle = rawVehicle is Map ? rawVehicle : const {};
    return MatchedDriver(
      id: id,
      firstName: firstName,
      rating: (json['rating'] as num?)?.toDouble(),
      tripCount: (json['tripCount'] as num?)?.toInt(),
      vehicleMake: vehicle['make'] as String? ?? json['vehicleMake'] as String?,
      vehicleModel:
          vehicle['model'] as String? ?? json['vehicleModel'] as String?,
      vehicleColor:
          vehicle['color'] as String? ?? json['vehicleColor'] as String?,
      plate: vehicle['plate'] as String? ?? json['plate'] as String?,
      photoAsset: json['photoAsset'] as String?,
      vehicleImageAsset: json['vehicleImageAsset'] as String?,
      languages: langs is List
          ? langs.whereType<String>().where((item) => item.isNotEmpty).toList()
          : const [],
      yearsOnMovera: (json['yearsOnMovera'] as num?)?.toInt(),
    );
  }
}
