import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/config/trip_zone_config.dart';
import 'package:movera_rider/core/config/rider_app_config.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/active_ride/application/route_change_controller.dart';
import 'package:movera_rider/features/active_ride/presentation/route_change_sheet.dart';
import 'package:movera_rider/features/destination_search/presentation/route_picker_page.dart';
import 'package:movera_rider/features/home/application/home_places_controller.dart';
import 'package:movera_rider/features/pickup/presentation/confirm_pickup_spot.dart';
import 'package:movera_rider/features/ride_booking/domain/route_stop.dart';
import 'package:movera_rider/features/wallet/application/wallet_controller.dart';
import 'package:movera_rider/shared/formatters/money.dart';
import 'package:movera_rider/shared/widgets/early_input_capture.dart';
import 'package:movera_rider/shared/widgets/navigation_transition.dart';
import 'package:movera_rider/features/payments/presentation/payment_labels.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// Which row of the ride details the rider tapped.
enum RouteChangeEntry { pickup, destination, newStop, stop }

/// Opens "Change route" for a live ride: the rider edits the pickup (while
/// the driver is still on the way), the destination or the stops; the new
/// price is shown and confirmed before the driver is told.
///
/// Returns the updated, saved snapshot, or null when nothing changed.
Future<RideSnapshot?> openRouteChange(
  BuildContext context, {
  required RideSnapshot ride,
  required RouteChangeEntry entry,
  required bool pickupLocked,
  bool driverAccepted = false,
  RouteChangeController? controller,
}) async {
  final changes =
      controller ??
      RouteChangeController(
        api: AppScope.instance.api,
        geocoding: AppScope.instance.geocoding,
        session: AppScope.instance.ride,
      );
  if (!changes.available) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(context.l10n.routeChangeUnavailable)),
    );
    return null;
  }
  final places = HomePlacesController();
  await places.load();
  if (!context.mounted) return null;
  final capture = EarlyInputCapture()..start();
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    final draft = await Navigator.of(context).push<Map<String, dynamic>>(
      BottomToTopTransition(
        RoutePickerPage(
          pageTitle: context.l10n.changeRoute,
          pickupAddress: ride.pickupAddress,
          destinationAddress: ride.destinationAddress,
          destinationPoint: GeoPoint(ride.destinationLat, ride.destinationLng),
          stops: [for (final stop in ride.stops) stop.address],
          stopPoints: [
            for (final stop in ride.stops)
              GeoPoint(stop.latitude, stop.longitude),
          ],
          stopsSupported: true,
          pickupLocked: pickupLocked,
          openWithNewStop: entry == RouteChangeEntry.newStop,
          initialField: switch (entry) {
            RouteChangeEntry.pickup when !pickupLocked => 'pickup',
            _ => 'destination',
          },
          finishLabel: context.l10n.seeNewPrice,
          capture: capture,
          here: GeoPoint(ride.pickupLat, ride.pickupLng),
          homeAddress: places.homeAddress,
          workAddress: places.workAddress,
          savedPlaces: places.savedPlaces,
          recent: places.recentAddresses,
          // rider-u40: no "Set your Home/Work" rows that do nothing here.
          onPickOnMap: ({required pickup, required address}) async {
            final start = pickup
                ? LatLng(ride.pickupLat, ride.pickupLng)
                : LatLng(ride.destinationLat, ride.destinationLng);
            final result = await ConfirmPickupSpot.open(
              context,
              initialPosition: start,
              initialAddress: address.isEmpty
                  ? (pickup ? ride.pickupAddress : ride.destinationAddress)
                  : address,
              title: pickup
                  ? context.l10n.confirmPickupSpot
                  : context.l10n.confirmDestination,
              confirmLabel: pickup
                  ? context.l10n.confirmPickup
                  : context.l10n.confirmDestination,
            );
            if (result == null) return null;
            return RoutePickerMapPick(
              address: result.address,
              point: GeoPoint(
                result.position.latitude,
                result.position.longitude,
              ),
            );
          },
          onFinish: (selection) async {
            try {
              final quote = await changes.preview(
                ride: ride,
                pickupAddress: pickupLocked ? null : selection.pickup,
                pickupPoint: pickupLocked ? null : selection.pickupPoint,
                destinationAddress: selection.destination,
                destinationPoint: selection.destinationPoint,
                stops: selection.stops,
                stopPoints: selection.stopPoints,
                // Q40: the trip zone's `booking.maxPickupMoveMeters`.
                maxPickupMoveMeters: driverAccepted
                    ? await _maxPickupMoveMeters(ride)
                    : null,
              );
              if (!context.mounted) return null;
              final decision = await RouteChangeSheet.confirm(
                context,
                quote: quote,
                paymentMethod: ride.paymentMethod,
                paymentMethodId: ride.paymentMethodId,
              );
              if (!decision.confirmed || !context.mounted) return null;
              final updated = await changes.apply(
                ride: ride,
                quote: quote,
                refundTo: decision.refundTo,
              );
              await _creditWallet(
                decision.refundTo,
                quote,
                before: ride,
                after: updated,
              );
              return {
                'ride': updated,
                'refundTo': decision.refundTo,
                'differenceKr': quote.differenceKr,
              };
            } on RouteChangeException catch (error) {
              messenger
                ?..hideCurrentSnackBar()
                ..showSnackBar(SnackBar(content: Text(error.message)));
              return null;
            }
          },
        ),
      ),
    );
    final updated = draft?['ride'];
    final refundTo = draft?['refundTo'];
    lastRefundDestination = refundTo is RefundDestination ? refundTo : null;
    final difference = draft?['differenceKr'];
    lastRouteDifferenceKr = difference is double ? difference : null;
    return updated is RideSnapshot ? updated : null;
  } finally {
    capture.stop();
  }
}

/// Q40: how far the pickup of [ride] may move after accept, from its
/// zone's config; the contract default when no config of the trip's
/// currency can be read.
Future<int> _maxPickupMoveMeters(RideSnapshot ride) async {
  try {
    final config = await AppScope.instance.riderConfig.forTrip(
      currency: ride.currency,
      pickupLat: ride.pickupLat,
      pickupLng: ride.pickupLng,
    );
    if (config != null) return config.maxPickupMoveMeters;
  } catch (_) {
    // The default below.
  }
  return RiderAppConfig.defaultMaxPickupMoveAfterAcceptMeters;
}

/// Where the last confirmed refund went, for the confirmation banner.
RefundDestination? lastRefundDestination;

/// rider-u36: the difference the server priced for the last confirmed
/// change (whole units), for the confirmation banner. The device's own
/// price can lag the server's, so `updated.price - ride.price` is only a
/// fallback.
double? lastRouteDifferenceKr;

/// A refund the rider sent to the Movera Wallet is credited right away.
///
/// rider-u42: the wallet part of a trip is only debited at completion, from
/// the saved (already lower) fare, so that part of the cut must not also be
/// credited now. Only what another method no longer pays is credited.
Future<void> _creditWallet(
  RefundDestination? refundTo,
  RouteChangeQuote quote, {
  required RideSnapshot before,
  required RideSnapshot after,
}) async {
  if (refundTo != RefundDestination.wallet || quote.differenceKr >= 0) return;
  try {
    final creditMinor = routeChangeWalletCreditMinor(
      quote: quote,
      before: before,
      after: after,
    );
    if (creditMinor <= 0) return;
    // Q8: the refund goes to the wallet balance of the trip's currency.
    final wallet = AppScope.instance.walletController.forCurrency(
      quote.currency,
    );
    final previous = await wallet.loadBalance();
    await wallet.refund(
      previous: previous,
      amount: Money(creditMinor, quote.currency).major,
    );
  } catch (_) {
    // The mock backend already holds the refund; the local ledger is a
    // convenience and must not block the route change.
  }
}

/// rider-u42: how much of a cheaper route change ([before] -> [after]) is
/// credited to the wallet now, in minor units of the quote's currency.
///
/// The completion charge (`WalletController.chargeCompletedRide`) debits a
/// wallet ride for its saved fare, and a "wallet first" ride for
/// min(wallet part, fare). Whatever that debit is now smaller by is already
/// the refund, so it is taken off the credit; only the rest (the part the
/// card no longer pays) is credited.
@visibleForTesting
int routeChangeWalletCreditMinor({
  required RouteChangeQuote quote,
  required RideSnapshot before,
  required RideSnapshot after,
}) {
  final refundMinor =
      -(quote.differenceMinor ??
          Money.fromLegacyMajor(
            quote.differenceKr,
            quote.currency,
          ).amountMinor);
  if (refundMinor <= 0) return 0;
  int walletPart(RideSnapshot ride) {
    final methodId = ride.paymentMethodId;
    final paidByWallet = methodId != null
        ? methodId == 'wallet'
        : WalletController.isWalletPayment(ride.paymentMethod);
    final fare = ride.fare.amountMinor;
    if (paidByWallet) return fare;
    final wallet = ride.walletAmountMinor;
    if (wallet <= 0) return 0;
    return wallet < fare ? wallet : fare;
  }

  final alreadyLess = walletPart(before) - walletPart(after);
  final credit = refundMinor - (alreadyLess > 0 ? alreadyLess : 0);
  return credit > 0 ? credit : 0;
}

/// The short confirmation shown after a route change went through.
void showRouteUpdated(
  BuildContext context, {
  required bool driverAssigned,
  String paymentMethod = '',
  double differenceKr = 0,
  String currency = Money.defaultCurrency,
  RefundDestination? refundTo,
}) {
  final parts = <String>[
    driverAssigned
        ? context.l10n.routeUpdatedDriverTold
        : context.l10n.routeUpdated,
  ];
  // rider-u43: any change in minor units is told, not only half a unit.
  if (!isCashPayment(paymentMethod) &&
      Money.fromLegacyMajor(differenceKr, currency).amountMinor != 0) {
    // [differenceKr] is in whole units of [currency].
    final kr = formatMajor(differenceKr.abs(), currency);
    // rider-u231: the method's name in the app language.
    final method = paymentLabelFor(paymentMethod);
    if (differenceKr > 0) {
      parts.add(context.l10n.chargedTo(kr, method));
    } else if ((refundTo ?? lastRefundDestination) ==
        RefundDestination.wallet) {
      parts.add(context.l10n.creditedToWallet(kr));
    } else {
      parts.add(context.l10n.refundedToDays(kr, method));
    }
  }
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        key: const ValueKey('route-updated-snack'),
        content: Text(parts.join(' · ')),
        duration: const Duration(seconds: 4),
      ),
    );
}

/// Removes one stop: prices the shorter route, confirms, applies.
Future<RideSnapshot?> removeRouteStop(
  BuildContext context, {
  required RideSnapshot ride,
  required int index,
  RouteChangeController? controller,
}) async {
  if (index < 0 || index >= ride.stops.length) return null;
  lastRouteDifferenceKr = null;
  final changes =
      controller ??
      RouteChangeController(
        api: AppScope.instance.api,
        geocoding: AppScope.instance.geocoding,
        session: AppScope.instance.ride,
      );
  final kept = [
    for (var i = 0; i < ride.stops.length; i++)
      if (i != index) ride.stops[i],
  ];
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    final quote = await changes.preview(
      ride: ride,
      destinationAddress: ride.destinationAddress,
      stops: [for (final stop in kept) stop.address],
      stopPoints: [
        for (final stop in kept) GeoPoint(stop.latitude, stop.longitude),
      ],
    );
    if (!context.mounted) return null;
    final decision = await RouteChangeSheet.confirm(
      context,
      quote: quote,
      paymentMethod: ride.paymentMethod,
      paymentMethodId: ride.paymentMethodId,
    );
    if (!decision.confirmed || !context.mounted) return null;
    final updated = await changes.apply(
      ride: ride,
      quote: quote,
      refundTo: decision.refundTo,
    );
    await _creditWallet(decision.refundTo, quote, before: ride, after: updated);
    lastRefundDestination = decision.refundTo;
    lastRouteDifferenceKr = quote.differenceKr;
    return updated;
  } on RouteChangeException catch (error) {
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(error.message)));
    return null;
  }
}

/// Markers for the stops between pickup and destination.
Set<Marker> routeStopMarkers(List<RouteStop> stops) => {
  for (var i = 0; i < stops.length; i++)
    Marker(
      markerId: MarkerId('stop-$i'),
      position: LatLng(stops[i].latitude, stops[i].longitude),
      infoWindow: InfoWindow(
        title: L10n.current.stopNumber('${i + 1}'),
        snippet: stops[i].address,
      ),
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
    ),
};

/// Pickup → stops → destination as one straight-line route.
List<LatLng> routeWithStops({
  required LatLng pickup,
  required List<RouteStop> stops,
  required LatLng destination,
}) => [
  pickup,
  for (final stop in stops) LatLng(stop.latitude, stop.longitude),
  destination,
];
