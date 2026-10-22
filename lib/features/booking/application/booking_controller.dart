import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/features/booking/application/booking_coordinator.dart';
import 'package:movera_rider/features/booking/data/booking_repository.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/quote.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_notes.dart';
import 'package:movera_rider/features/ride_booking/domain/route_stop.dart';

class BookingController {
  BookingController({BookingRepository? store})
      : _store = store ?? BookingRepository();
  final BookingRepository _store;

  /// RC-09: the booking failed in a way that may still have created the
  /// ride (timeout, dropped connection, 5xx) after its own recovery.
  static bool mayHaveBooked(Object error) =>
      BookingCoordinator.maybeCreated(error);

  /// rider-u107: a fresh quote for booking the same route again.
  Future<RideQuote> freshQuote({
    required String rideType,
    required String pickupAddress,
    required String destinationAddress,
    required double pickupLat,
    required double pickupLng,
    required double destinationLat,
    required double destinationLng,
    List<RouteStop> stops = const <RouteStop>[],
  }) => _store.freshQuote(
    rideType: rideType,
    pickupAddress: pickupAddress,
    destinationAddress: destinationAddress,
    pickupLat: pickupLat,
    pickupLng: pickupLng,
    destinationLat: destinationLat,
    destinationLng: destinationLng,
    stops: stops,
  );

  Future<String> submitFinding({
    required String pickupAddress,
    required String destinationAddress,
    required double pickupLat,
    required double pickupLng,
    required double destinationLat,
    required double destinationLng,
    required String rideType,
    required double price,
    required String paymentMethod,
    String? quoteId,
    String? quoteSignedPayload,
    DateTime? quoteExpiresAt,
    int? quoteTotalMinor,
    String quoteCurrency = Money.defaultCurrency,
    String? rideTypeLabel,
    String? paymentMethodLabel,
    RideNotes notes = RideNotes.empty,
    List<RouteStop> stops = const <RouteStop>[],
    bool useWalletFirst = false,
    int walletAmountMinor = 0,
  }) {
    return _store.submitFinding(
      pickupAddress: pickupAddress,
      destinationAddress: destinationAddress,
      pickupLat: pickupLat,
      pickupLng: pickupLng,
      destinationLat: destinationLat,
      destinationLng: destinationLng,
      rideType: rideType,
      price: price,
      paymentMethod: paymentMethod,
      quoteId: quoteId,
      quoteSignedPayload: quoteSignedPayload,
      quoteExpiresAt: quoteExpiresAt,
      quoteTotalMinor: quoteTotalMinor,
      quoteCurrency: quoteCurrency,
      rideTypeLabel: rideTypeLabel,
      paymentMethodLabel: paymentMethodLabel,
      notes: notes,
      stops: stops,
      useWalletFirst: useWalletFirst,
      walletAmountMinor: walletAmountMinor,
    );
  }
  Future<String> reconcileCreatedFinding(String createdRideId) {
    return _store.reconcileCreatedFinding(createdRideId);
  }

}
