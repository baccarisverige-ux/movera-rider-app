/// The ordering chips above the Select Ride list.
enum SelectRideFilter { recommended, faster, cheaper }

/// Returns [rides] in the order [filter] shows them, without mutating the
/// input. Recommended keeps catalog order. Cheaper compares [price] (Select
/// Ride passes the fare each tile shows, rider-r3-7).
List<T> orderRidesForFilter<T>(
  Iterable<T> rides,
  SelectRideFilter filter, {
  required int Function(T ride) etaMin,
  required double Function(T ride) price,
}) {
  final ordered = [...rides];
  switch (filter) {
    case SelectRideFilter.faster:
      ordered.sort((a, b) => etaMin(a).compareTo(etaMin(b)));
      break;
    case SelectRideFilter.cheaper:
      ordered.sort((a, b) => price(a).compareTo(price(b)));
      break;
    case SelectRideFilter.recommended:
      break;
  }
  return ordered;
}
