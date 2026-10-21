import 'package:movera_rider/core/contracts/category_ids.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/features/reservations/domain/reservation_status.dart';
import 'package:movera_rider/features/trips/domain/trip.dart';
import 'package:movera_rider/shared/formatters/name_format.dart';
import 'package:movera_rider/shared/formatters/money.dart';
import 'package:movera_rider/l10n/l10n.dart';

class ReservationPlace {
  const ReservationPlace({
    required this.label,
    this.subtitle,
    this.lat,
    this.lng,
  });

  final String label;
  final String? subtitle;
  final double? lat;
  final double? lng;

  ReservationPlace copyWith({
    String? label,
    String? subtitle,
    double? lat,
    double? lng,
  }) {
    return ReservationPlace(
      label: label ?? this.label,
      subtitle: subtitle ?? this.subtitle,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
    );
  }

  Map<String, dynamic> toJson() => {
    'label': label,
    if (subtitle != null) 'subtitle': subtitle,
    if (lat != null) 'lat': lat,
    if (lng != null) 'lng': lng,
  };

  static ReservationPlace? tryParse(dynamic raw) {
    if (raw is String && raw.trim().isNotEmpty) {
      return ReservationPlace(label: raw.trim());
    }
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final label = (map['label'] as String?)?.trim() ?? '';
    if (label.isEmpty) return null;
    return ReservationPlace(
      label: label,
      subtitle: map['subtitle'] as String?,
      lat: (map['lat'] as num?)?.toDouble(),
      lng: (map['lng'] as num?)?.toDouble(),
    );
  }
}

class ReservationDriver {
  const ReservationDriver({
    required this.firstName,
    this.id,
    this.rating,
    this.vehicle,
    this.vehicleColor,
    this.plate,
    this.photoAsset,
  });

  final String firstName;

  /// Dispatch's id for the driver, when it sends one.
  final String? id;
  final double? rating;
  final String? vehicle;
  final String? vehicleColor;
  final String? plate;
  final String? photoAsset;

  String get normalizedFirstName => firstName.trim();

  bool get hasFirstName => normalizedFirstName.isNotEmpty;

  String get displayFirstName =>
      hasFirstName ? normalizedFirstName : 'Driver';

  String get initial => initialFromName(normalizedFirstName);

  /// "Black Volvo XC40", or null when dispatch sent no car.
  String? get carLabel {
    final car = vehicle?.trim() ?? '';
    if (car.isEmpty) return null;
    final color = vehicleColor?.trim() ?? '';
    return color.isEmpty ? car : '$color $car';
  }

  /// Same person: by id when both have one, else by name and plate.
  bool isSameAs(ReservationDriver other) {
    if (id != null && other.id != null) return id == other.id;
    return normalizedFirstName == other.normalizedFirstName &&
        plate == other.plate;
  }

  Map<String, dynamic> toJson() => {
    'firstName': firstName,
    if (id != null) 'id': id,
    if (rating != null) 'rating': rating,
    if (vehicle != null) 'vehicle': vehicle,
    if (vehicleColor != null) 'vehicleColor': vehicleColor,
    if (plate != null) 'plate': plate,
    if (photoAsset != null) 'photoAsset': photoAsset,
  };

  static ReservationDriver? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final name = (map['firstName'] as String?)?.trim() ?? '';
    if (name.isEmpty) return null;
    return ReservationDriver(
      firstName: name,
      id: map['id'] as String?,
      rating: (map['rating'] as num?)?.toDouble(),
      vehicle: map['vehicle'] as String?,
      vehicleColor: map['vehicleColor'] as String?,
      plate: map['plate'] as String?,
      photoAsset: map['photoAsset'] as String?,
    );
  }
}

class ReservationDraft {
  const ReservationDraft({
    required this.scheduledPickupAt,
    required this.pickup,
    required this.destination,
    required this.categoryId,
    required this.categoryName,
    required this.categoryImage,
    required this.price,
    required this.paymentMethod,
    this.passengerCount = 4,
    this.currency = 'SEK',
    this.estimatedDropoffAt,
    this.note,
    this.parentReservationId,
  });

  final DateTime scheduledPickupAt;
  final ReservationPlace pickup;
  final ReservationPlace destination;
  final String categoryId;
  final String categoryName;
  final String categoryImage;
  final int passengerCount;
  final double price;
  final String currency;
  final String paymentMethod;
  final DateTime? estimatedDropoffAt;
  final String? note;
  final String? parentReservationId;
}

class ReservationPriceChange {
  const ReservationPriceChange({
    required this.previous,
    required this.next,
    this.currency = 'SEK',
  });

  /// Whole units of [currency] (the ride's).
  final double previous;
  final double next;
  final String currency;

  double get delta => next - previous;

  bool get unchanged => delta.abs() < 0.5;

  String get summary {
    if (unchanged) return L10n.current.resPriceUnchanged;
    final amount = formatMajor(delta.abs(), currency);
    if (delta > 0) return L10n.current.resCostsMore(amount);
    return L10n.current.resCostsLess(amount);
  }
}

class ReservationPatch {
  const ReservationPatch({
    this.scheduledPickupAt,
    this.estimatedDropoffAt,
    this.pickup,
    this.destination,
    this.categoryId,
    this.categoryName,
    this.categoryImage,
    this.passengerCount,
    this.paymentMethod,
    this.price,
    this.currency,
    this.note,
    this.status,
    this.driver,
    this.clearDriver = false,
    this.previousDriver,
  });

  final DateTime? scheduledPickupAt;
  final DateTime? estimatedDropoffAt;
  final ReservationPlace? pickup;
  final ReservationPlace? destination;
  final String? categoryId;
  final String? categoryName;
  final String? categoryImage;
  final int? passengerCount;
  final String? paymentMethod;
  final double? price;

  /// ISO-4217 code of [price], when it changes with it.
  final String? currency;
  final String? note;
  final ReservationStatus? status;
  final ReservationDriver? driver;
  final bool clearDriver;

  /// The driver who handed this ride over, when the driver changes.
  final ReservationDriver? previousDriver;
}

class Reservation {
  const Reservation({
    required this.reservationId,
    required this.createdAt,
    required this.scheduledPickupAt,
    required this.pickup,
    required this.destination,
    required this.categoryId,
    required this.categoryName,
    required this.categoryImage,
    required this.price,
    required this.paymentMethod,
    required this.status,
    this.passengerCount = 4,
    this.currency = 'SEK',
    this.estimatedDropoffAt,
    this.driver,
    this.note,
    this.cancellationReason,
    this.cancellationActor,
    this.cancelledAt,
    this.policyVersion,
    this.parentReservationId,
    this.previousDriver,
    this.cancellationFee,
    this.endedEarly = false,
    this.chargedFare,
    this.paymentFailed = false,
  });

  final String reservationId;
  final DateTime createdAt;
  final DateTime scheduledPickupAt;
  final DateTime? estimatedDropoffAt;
  final ReservationPlace pickup;
  final ReservationPlace destination;
  final String categoryId;
  final String categoryName;
  final String categoryImage;
  final int passengerCount;
  final double price;
  final String currency;
  final String paymentMethod;
  final ReservationStatus status;
  final ReservationDriver? driver;
  final String? note;
  final String? cancellationReason;
  final TripCancellationActor? cancellationActor;
  final DateTime? cancelledAt;
  final String? policyVersion;
  final String? parentReservationId;

  /// The driver who accepted this ride before the current one, or before
  /// the search for a new one. Kept so the rider is told the driver changed.
  final ReservationDriver? previousDriver;

  /// The fee the rider agreed to when cancelling late, if any.
  final Money? cancellationFee;

  /// UI-01: the rider ended the trip on board (contract `end_early`). The
  /// ride is `cancelled`, but they paid for the distance driven.
  final bool endedEarly;

  /// What the server said the rider pays, when known (an ended-early
  /// trip's final `fare`). Null: only [price], the booked price, is known.
  final Money? chargedFare;

  /// rider-37: the trip was completed but its payment failed (contract
  /// `paymentStatus: failed`). History lists it as completed and says so.
  final bool paymentFailed;

  bool get driverAssigned => status.hasDriver && driver != null;

  bool get isSearchingDriver => status.isSearchingDriver;

  bool get revealsDriver => status.isDriverOnTheWay && driver != null;

  bool get hasPreferences => note != null && note!.trim().isNotEmpty;

  /// A different driver now has the ride than the one who accepted first.
  bool get driverChanged {
    final current = driver;
    final before = previousDriver;
    return current != null && before != null && !current.isSameAs(before);
  }

  Reservation copyWith({
    DateTime? scheduledPickupAt,
    DateTime? estimatedDropoffAt,
    ReservationPlace? pickup,
    ReservationPlace? destination,
    String? categoryId,
    String? categoryName,
    String? categoryImage,
    int? passengerCount,
    double? price,
    String? currency,
    String? paymentMethod,
    ReservationStatus? status,
    ReservationDriver? driver,
    String? note,
    String? cancellationReason,
    TripCancellationActor? cancellationActor,
    DateTime? cancelledAt,
    String? policyVersion,
    String? parentReservationId,
    bool clearDriver = false,
    ReservationDriver? previousDriver,
    Money? cancellationFee,
    bool? endedEarly,
    Money? chargedFare,
    bool? paymentFailed,
  }) {
    return Reservation(
      reservationId: reservationId,
      createdAt: createdAt,
      scheduledPickupAt: scheduledPickupAt ?? this.scheduledPickupAt,
      estimatedDropoffAt: estimatedDropoffAt ?? this.estimatedDropoffAt,
      pickup: pickup ?? this.pickup,
      destination: destination ?? this.destination,
      categoryId: categoryId ?? this.categoryId,
      categoryName: categoryName ?? this.categoryName,
      categoryImage: categoryImage ?? this.categoryImage,
      passengerCount: passengerCount ?? this.passengerCount,
      price: price ?? this.price,
      currency: currency ?? this.currency,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      status: status ?? this.status,
      driver: clearDriver ? null : (driver ?? this.driver),
      note: note ?? this.note,
      cancellationReason: cancellationReason ?? this.cancellationReason,
      cancellationActor: cancellationActor ?? this.cancellationActor,
      cancelledAt: cancelledAt ?? this.cancelledAt,
      policyVersion: policyVersion ?? this.policyVersion,
      parentReservationId: parentReservationId ?? this.parentReservationId,
      previousDriver: previousDriver ?? this.previousDriver,
      cancellationFee: cancellationFee ?? this.cancellationFee,
      endedEarly: endedEarly ?? this.endedEarly,
      chargedFare: chargedFare ?? this.chargedFare,
      paymentFailed: paymentFailed ?? this.paymentFailed,
    );
  }

  Map<String, dynamic> toJson() => {
    'reservationId': reservationId,
    'createdAt': createdAt.toIso8601String(),
    'scheduledPickupAt': scheduledPickupAt.toIso8601String(),
    if (estimatedDropoffAt != null)
      'estimatedDropoffAt': estimatedDropoffAt!.toIso8601String(),
    'pickup': pickup.toJson(),
    'destination': destination.toJson(),
    'categoryId': categoryId,
    'categoryName': categoryName,
    'categoryImage': categoryImage,
    'passengerCount': passengerCount,
    'price': price,
    'currency': currency,
    'paymentMethod': paymentMethod,
    'status': status.name,
    if (driver != null) 'driver': driver!.toJson(),
    if (note != null) 'note': note,
    if (cancellationReason != null) 'cancellationReason': cancellationReason,
    if (cancellationActor != null) 'cancellationActor': cancellationActor!.name,
    if (cancelledAt != null) 'cancelledAt': cancelledAt!.toIso8601String(),
    if (policyVersion != null) 'policyVersion': policyVersion,
    if (parentReservationId != null) 'parentReservationId': parentReservationId,
    if (previousDriver != null) 'previousDriver': previousDriver!.toJson(),
    if (cancellationFee != null) 'cancellationFee': cancellationFee!.toJson(),
    if (endedEarly) 'endedEarly': true,
    if (chargedFare != null) 'chargedFare': chargedFare!.toJson(),
    if (paymentFailed) 'paymentFailed': true,
  };

  static Reservation? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    try {
      final map = Map<String, dynamic>.from(raw);
      final id =
          (map['reservationId'] as String?)?.trim() ??
          (map['id'] as String?)?.trim() ??
          '';
      if (id.isEmpty) return null;
      final pickup = ReservationPlace.tryParse(map['pickup']);
      final destination = ReservationPlace.tryParse(map['destination']);
      if (pickup == null || destination == null) return null;
      final created = DateTime.tryParse(map['createdAt'] as String? ?? '');
      final pickupAt = DateTime.tryParse(
        map['scheduledPickupAt'] as String? ?? map['pickupAt'] as String? ?? '',
      );
      if (created == null || pickupAt == null) return null;
      final rawStatus = map['status'] as String?;
      final status = rawStatus == null
          ? ReservationStatus.scheduled
          : ReservationStatus.tryParse(rawStatus);
      if (status == null) return null;
      return Reservation(
        reservationId: id,
        createdAt: created,
        scheduledPickupAt: pickupAt,
        estimatedDropoffAt: DateTime.tryParse(
          map['estimatedDropoffAt'] as String? ?? '',
        ),
        pickup: pickup,
        destination: destination,
        categoryId: CategoryIds.canonical(
          (map['categoryId'] as String?) ?? CategoryIds.economy,
        ),
        categoryName: (map['categoryName'] as String?) ?? 'Movera',
        categoryImage:
            (map['categoryImage'] as String?) ??
            'assets/images/rides/movera.webp',
        passengerCount: (map['passengerCount'] as num?)?.toInt() ?? 4,
        price: (map['price'] as num?)?.toDouble() ?? 0,
        currency: (map['currency'] as String?) ?? 'SEK',
        paymentMethod: (map['paymentMethod'] as String?) ?? 'Apple Pay',
        status: status,
        driver: ReservationDriver.tryParse(map['driver']),
        note: map['note'] as String?,
        cancellationReason: map['cancellationReason'] as String?,
        cancellationActor: _parseCancellationActor(
          map['cancellationActor'] as String?,
        ),
        cancelledAt: DateTime.tryParse(map['cancelledAt'] as String? ?? ''),
        policyVersion: map['policyVersion'] as String?,
        parentReservationId: map['parentReservationId'] as String?,
        previousDriver: ReservationDriver.tryParse(map['previousDriver']),
        cancellationFee: Money.fromWire(map['cancellationFee']),
        endedEarly: map['endedEarly'] == true,
        chargedFare: Money.fromWire(map['chargedFare']),
        paymentFailed: map['paymentFailed'] == true,
      );
    } catch (_) {
      return null;
    }
  }
}


TripCancellationActor? _parseCancellationActor(String? name) {
  if (name == null) return null;
  for (final actor in TripCancellationActor.values) {
    if (actor.name == name) return actor;
  }
  return null;
}
