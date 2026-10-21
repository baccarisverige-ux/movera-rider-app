import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/features/history/application/on_demand_history_controller.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/support/data/support_repository.dart';
import 'package:movera_rider/features/support/domain/support.dart';
import 'package:movera_rider/l10n/l10n.dart';

class SupportController {
  SupportController({
    SupportRepository? store,
    Future<List<Reservation>> Function()? onDemand,
    List<Reservation> Function()? scheduled,
  })  : _store = store ?? SupportRepository(),
        _onDemand = onDemand,
        _scheduled = scheduled;
  final SupportRepository _store;
  final Future<List<Reservation>> Function()? _onDemand;
  final List<Reservation> Function()? _scheduled;
  static const _history = OnDemandHistoryController();

  /// FLOW-8: the rides Support can be asked about are the ones Ride History
  /// shows (finished and cancelled, on-demand and scheduled), newest first.
  Future<List<SupportRide>> loadRides() async {
    final onDemand = await (_onDemand ?? _history.load)();
    final scheduled =
        (_scheduled ?? () => AppScope.instance.reservations.all)();
    final rides = [
      ..._history.combine(scheduled, onDemand, completed: true),
      ..._history.combine(scheduled, onDemand, completed: false),
    ]..sort((a, b) => b.scheduledPickupAt.compareTo(a.scheduledPickupAt));
    return [for (final ride in rides) rideFor(ride)];
  }

  SupportChatScript chat({SupportRide? ride}) => _store.chat(ride: ride);

  /// The Support row for a History ride (also "Get help" in History).
  static SupportRide rideFor(Reservation ride) {
    final to = ride.destination.label.trim();
    final charged = ride.chargedFare;
    return SupportRide(
      id: ride.reservationId,
      title: to.isEmpty ? ride.categoryName : L10n.current.toPlace(to),
      // rider-63: a zone booking reads in its pickup zone's time.
      when: ride.timeZone == null
          ? ride.scheduledPickupAt.toLocal()
          : ride.pickupWallTime,
      // rider-r4-37: an ended-early trip is cancelled but charged, so it
      // shows the server's final fare, as History does.
      price: charged?.major ?? ride.price,
      currency: charged?.currency ?? ride.currency,
      image: ride.categoryImage,
      cancelled: ride.status.isCancelled && !ride.endedEarly,
      endedEarly: ride.endedEarly,
    );
  }
}
