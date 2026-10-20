import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/features/booking/application/booking_coordinator.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_notes.dart';
import 'package:movera_rider/features/ride_booking/domain/route_stop.dart';

class BookingRepository {
  BookingRepository({BookingCoordinator? coordinator})
    : _coordinator = coordinator ?? AppScope.instance.booking;

  final BookingCoordinator _coordinator;

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
    return _coordinator.submitFinding(
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
    return _coordinator.reconcileCreatedFinding(createdRideId);
  }

}
