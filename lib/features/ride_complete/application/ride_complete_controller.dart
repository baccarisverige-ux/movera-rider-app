import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/config/rider_app_config.dart';
import 'package:movera_rider/core/config/trip_zone_config.dart';
import 'package:movera_rider/core/config/rider_zones.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/core/location/location_repository.dart';
import 'package:movera_rider/features/active_ride/application/active_ride_controller.dart';
import 'package:movera_rider/features/ride_booking/data/driver_repository.dart';
import 'package:movera_rider/features/ride_complete/data/ride_complete_repository.dart';
import 'package:movera_rider/features/ride_complete/data/ride_dispute_repository.dart';
import 'package:movera_rider/features/ride_complete/data/ride_feedback_repository.dart';
import 'package:movera_rider/features/ride_complete/data/last_completed_ride.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';

class RideCompleteController {
  RideCompleteController({
    ActiveRideController? ride,
    DriverRepository? drivers,
    TripReceiptRepository? trips,
    TipCatalog? tips,
    RideDisputeRepository? disputes,
    RideFeedbackRepository? feedback,
    RiderConfigRepository? config,
    this.tipsOnServer = true,
    Future<String?> Function(String rideId)? serverCurrency,
  }) : _config = config,
       _serverCurrency = serverCurrency ?? _readServerCurrency,
       _ride = ride ?? ActiveRideController(),
       _drivers = drivers ?? const DriverRepository(),
       _trips = trips ?? const TripReceiptRepository(),
       _tips = tips ?? const TipCatalog(),
       _disputes = disputes ?? RideDisputeRepository(),
       _feedback = feedback ?? RideFeedbackRepository();

  final ActiveRideController _ride;
  final DriverRepository _drivers;
  final TripReceiptRepository _trips;
  final TipCatalog _tips;
  final RideDisputeRepository _disputes;
  final RideFeedbackRepository _feedback;
  final RiderConfigRepository? _config;
  final Future<String?> Function(String rideId) _serverCurrency;

  /// Deep re-check P2-M2: the currency of a trip the completion screen
  /// shows after a reload, when [LastCompletedRide] (memory only) is empty.
  static final Map<String, String> _knownCurrency = {};

  /// `GET /trips/{tripId}` → `fare.currency`; null on any failure.
  static Future<String?> _readServerCurrency(String rideId) async {
    try {
      final api = AppScope.instance.api;
      if (!api.contractWire) return null;
      final trip = await api.get(api.tripPath(rideId));
      final fare = trip['fare'];
      final currency = fare is Map ? fare['currency'] : null;
      return currency is String && currency.trim().isNotEmpty
          ? currency.trim()
          : null;
    } catch (_) {
      return null;
    }
  }

  /// The trip's currency: the ride in hand, else the server's trip, else
  /// the zone of the last good position on this phone, else the home
  /// zone's. Never kronor by default for a French trip.
  Future<String> tripCurrency(String? rideId) async {
    final known = _tripCurrencyOrNull(rideId);
    if (known != null) return known;
    final id = rideId?.trim();
    if (id != null && id.isNotEmpty) {
      final server = await _serverCurrency(id);
      if (server != null) return _knownCurrency[id] = server;
    }
    final zone = await LocationRepository.readLastZone();
    final currency = zone?.currency ?? RiderZones.home.currency;
    if (id != null && id.isNotEmpty) _knownCurrency[id] = currency;
    return currency;
  }

  String? _tripCurrencyOrNull(String? rideId) {
    final ride = LastCompletedRide.forRide(rideId)?.currency;
    if (ride != null) return ride;
    final id = rideId?.trim();
    return id == null ? null : _knownCurrency[id];
  }

  /// False hides the tip amounts (the honest "Tips unavailable" state).
  /// movera-server takes tips since contract v0.18.10.
  final bool tipsOnServer;

  void close() => _ride.markClosed();
  Future<void> closeCompletedRide(String rideId) =>
      _ride.closeCompletedRide(rideId);
  Future<void> submitFeedback({
    required String rideId,
    double? rating,
    int? tipMinor,
    List<String> tags = const <String>[],
    String? comment,
    required String idempotencyKey,
  }) async => _feedback.submit(
    rideId: rideId,
    rating: rating,
    tipMinor: tipMinor,
    tags: tags,
    comment: comment,
    // Q5: the tip is in the trip's own currency, never assumed kronor
    // (P2-M2: also after a reload of the finish screen).
    tipCurrency: await tripCurrency(rideId),
    idempotencyKey: idempotencyKey,
  );
  Future<void> chargeCompletedWallet(String rideId) =>
      _ride.chargeCompletedWallet(rideId);
  Future<void> markCompletedPaymentFailed(String rideId) =>
      _ride.markCompletedPaymentFailed(rideId);
  Future<void> markPaymentRetried(String rideId, RideStatus status) =>
      _ride.markPaymentRetried(rideId, status);
  Future<void> persistCompletedStatus(
    RideStatus status, {
    required String rideId,
  }) => _ride.persistCompletedStatus(status, rideId: rideId);
  // rider-u166: [rideId] is the ride the completion screen shows; another
  // ride remembered in LastCompletedRide is never shown for it.
  DriverProfile? driver({String? rideId}) => _drivers.current(rideId: rideId);
  TripReceipt? receipt({String? rideId}) => _trips.last(rideId: rideId);
  String _tripCurrency(String? rideId) =>
      _tripCurrencyOrNull(rideId) ?? Money.defaultCurrency;

  /// The tip options to show before the zone's config is read: the fixed
  /// catalog when one was given, else the built-in seed of the trip's
  /// currency (owner Q5: 10/20/30 kr, 1/2/5 €, 1/2/3 DT).
  List<Money> initialTips({String? rideId}) => !tipsOnServer
      ? const <Money>[]
      : _tips.fixed ??
            seedConfigForTrip(_tripCurrency(rideId))?.enabledTips ??
            const <Money>[];

  /// The tip options of the trip's zone (Q5): its enabled `tips`, in its
  /// currency. Falls back to [initialTips] when no config of that currency
  /// can be read.
  Future<List<Money>> tips({String? rideId}) async {
    if (!tipsOnServer) return const <Money>[];
    final fixed = _tips.fixed;
    if (fixed != null) return fixed;
    final ride = LastCompletedRide.forRide(rideId);
    final currency = await tripCurrency(rideId);
    final config = await (_config ?? AppScope.instance.riderConfig).forTrip(
      currency: currency,
      pickupLat: ride?.pickupLat,
      pickupLng: ride?.pickupLng,
    );
    return config?.enabledTips ?? initialTips(rideId: rideId);
  }

  /// v0.18.10 `RiderAppConfig.tipRules` of the trip's zone: a typed
  /// amount up to its max when the admin allows it.
  Future<TipRules> tipRules({String? rideId}) async {
    final ride = LastCompletedRide.forRide(rideId);
    final currency = await tripCurrency(rideId);
    final config = await (_config ?? AppScope.instance.riderConfig).forTrip(
      currency: currency,
      pickupLat: ride?.pickupLat,
      pickupLng: ride?.pickupLng,
    );
    return config?.tipRules ??
        TipRules.forCountry(ZoneDefaults.countryOf(currency), currency);
  }

  Future<void> submitDispute({
    required String rideId,
    required String reason,
    String? detail,
  }) => _disputes.submit(rideId: rideId, reason: reason, detail: detail);
}
