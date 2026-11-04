part of 'waiting_for_driver.dart';

class _CancellingCard extends StatelessWidget {
  const _CancellingCard();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                context.l10n.findCancelling,
                style: waitingText(15, weight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// D-015: shown when the ride's realtime stream itself errored or closed, so
/// the driver marker is frozen rather than the driver standing still.
class LiveFeedDegradedBanner extends StatelessWidget {
  const LiveFeedDegradedBanner({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      container: true,
      label: context.l10n.livePaused,
      child: DecoratedBox(
        key: const ValueKey('waiting-live-feed-degraded'),
        decoration: BoxDecoration(
          color: const Color(0xF71D252C),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
          child: Row(
            children: [
              const Icon(
                Icons.portable_wifi_off_rounded,
                size: 18,
                color: Colors.white,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ExcludeSemantics(
                  child: Text(
                    context.l10n.livePaused,
                    style: waitingText(12.5, color: Colors.white),
                  ),
                ),
              ),
              TextButton(
                onPressed: onRetry,
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                child: Text(context.l10n.retry),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What "Search again" books: the ended trip's route, category, payment and
/// the price the rider saw.
class _SearchAgainTrip {
  const _SearchAgainTrip({
    required this.categoryId,
    required this.paymentMethodId,
    required this.pickupAddress,
    required this.pickup,
    required this.destinationAddress,
    required this.destination,
    required this.stops,
    required this.fare,
  });

  final String categoryId;
  final String paymentMethodId;

  /// Empty when the pickup is where the car stopped: the street is looked
  /// up when booking.
  final String pickupAddress;
  final LatLng pickup;
  final String destinationAddress;
  final LatLng destination;
  final List<RouteStop> stops;
  final Money fare;
}
