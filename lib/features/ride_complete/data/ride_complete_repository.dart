import 'package:movera_rider/core/contracts/money.dart';

/// A fixed list of tip options, for a build or a test that does not take
/// them from the zone's config.
///
/// The app normally offers the trip zone's `tips` (owner Q5: set per
/// market in Admin, in the zone's currency; see
/// `RideCompleteController.tips`). An empty catalog is still honoured: the
/// screen falls back to its unavailable state rather than inventing one.
class TipCatalog {
  const TipCatalog({List<Money>? amounts}) : _amounts = amounts;

  final List<Money>? _amounts;

  /// The fixed options, or null to use the zone's.
  List<Money>? get fixed => _amounts;
}
