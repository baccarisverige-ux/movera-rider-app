part of 'waiting_for_driver.dart';

class WaitingForDriver extends StatefulWidget {
  /// G7 live fix: how long "the driver refused / you withdrew / accepted"
  /// stays (a close button ends it sooner); the default 4 s was too short.
  /// G7: what the three dots open. With `routeChange.beforePickup` off
  /// before boarding only the destination and the stops are refused: the
  /// pickup still moves while the driver is on the way (owner decision).
  static DetailsAction detailsAction({
    required bool beforePickupOff,
    required bool pickupEditable,
  }) {
    if (!beforePickupOff) return DetailsAction.routeScreen;
    return pickupEditable ? DetailsAction.movePickup : DetailsAction.refused;
  }

  static const routeOutcomeNoticeDuration = Duration(seconds: 10);

  const WaitingForDriver({
    super.key,
    required this.pickupAddress,
    required this.destinationAddress,
    required this.pickupPosition,
    required this.destinationPosition,
    required this.rideType,
    required this.price,
    this.currency = Money.defaultCurrency,
    required this.paymentMethod,
    this.walletAmountMinor = 0,
    this.notes = RideNotes.empty,
    this.stops = const <RouteStop>[],
    this.driver,
    this.realtime,
    this.rideId,
    this.categoryId,
    this.persistRideSnapshot = true,
    this.routeChangeSupported = true,
    this.onTerminal,
    this.onDriverCancelled,
    this.onCompleted,
    this.onCancel,
    this.cancelFeeNote,
    this.controller,
    this.location,
    this.pickupMove,
  });

  final String pickupAddress;
  final String destinationAddress;
  final LatLng pickupPosition;
  final LatLng destinationPosition;
  final String rideType;

  /// Where the rider's phone is, for a Ride check at the end of a trip the
  /// live wire reports without a driver position (tests pass a fake). The
  /// app's own repository when null.
  final LocationRepository? location;

  /// The fare in whole units of [currency].
  final double price;

  /// Q7: the trip's currency (its pickup's zone).
  final String currency;
  final String paymentMethod;

  /// The part of the fare booked to the Movera Wallet, in öre.
  final int walletAmountMinor;
  final RideNotes notes;

  /// Stops between the pickup and the destination, in order.
  final List<RouteStop> stops;
  final MatchedDriver? driver;

  /// Optional transport and lifecycle overrides let Scheduled Ride reuse this
  /// exact presentation without touching the on-demand ride session.
  final RideRealtime? realtime;
  final String? rideId;

  /// rider-u44: the trip's own category id, for its waiting terms and the
  /// cancel-fee preview (a reservation's). Null: the Book Now session's
  /// booked category of [rideId], else the stored snapshot's.
  final String? categoryId;
  final bool persistRideSnapshot;

  /// rider-u55: false for a scheduled ride's live page. Its ride id is the
  /// device-local reservation id the server has no route quote for, so
  /// Change route and "change destination instead" can never succeed.
  final bool routeChangeSupported;
  final Future<void> Function(BuildContext context, RideStatus status)?
  onTerminal;
  final Future<void> Function(BuildContext context)? onDriverCancelled;
  final Future<void> Function(BuildContext context, RideStatus status)?
  onCompleted;
  final Future<void> Function(BuildContext context, String? reasonId)? onCancel;

  /// rider-u53: the fee line of the cancel sheet when the trip's cancel
  /// terms are not the live Book Now rule (a reservation's late-cancel
  /// terms). Null: the live rule of the trip's category is previewed.
  final Future<String?> Function()? cancelFeeNote;

  /// Test seam: the controller the cancel and end-early requests go
  /// through (its API client). Production uses the shared one.
  final ActiveRideController? controller;

  /// v0.18.7 (item 4): moves the pickup on the server (`PATCH
  /// /trips/{tripId}`), on the contract wire; the demo's route screen
  /// otherwise. Tests pass their own.
  final PickupMoveController? pickupMove;

  /// Test seam: the clock the live cancel fee preview is worked out with.
  @visibleForTesting
  static DateTime Function() cancelFeeClock = DateTime.now;

  @override
  State<WaitingForDriver> createState() => _WaitingForDriverState();
}
