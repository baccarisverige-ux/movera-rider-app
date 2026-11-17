import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/feature_flags/feature_flags.dart';
import 'package:movera_rider/features/ride_booking/data/catalog_quote_repository.dart';
import 'package:movera_rider/features/ride_selection/application/ride_selection_controller.dart';
import 'package:movera_rider/features/ride_selection/data/ride_selection_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// G26 / G-S2 (screen-switch report 2026-11-12, 3/3): the vehicle list
/// showed "0.000 DT" on every car for ~0.7 s. A zone's catalog row has no
/// list price in the zone currency (ride_catalog_controller.dart _withConfig:
/// 0.0 "until quoted"), yet hasPriceFor said "has a price" because the
/// currencies match, so select_ride_tiles.dart drew _kr(0).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  RideSelectionController make() => RideSelectionController(
    store: RideSelectionRepository(),
    quotes: CatalogQuoteRepository(),
    flags: FeatureFlags(),
    currency: 'TND',
  );

  test('a 0 list price before the quote is no price (shows the loader)', () {
    final selection = make();
    expect(
      selection.hasPriceFor('economy', catalogCurrency: 'TND', catalogPrice: 0),
      isFalse,
    );
  });

  test('selecting a ride with a 0 list price does not hold 0 as its fare', () {
    final selection = make()..selectRide('economy', 0, catalogCurrency: 'TND');
    expect(
      selection.hasPriceFor('economy', catalogCurrency: 'TND', catalogPrice: 0),
      isFalse,
    );
  });

  test('a real list price in the zone currency is still shown', () {
    final selection = make();
    expect(
      selection.hasPriceFor(
        'economy',
        catalogCurrency: 'TND',
        catalogPrice: 4.15,
      ),
      isTrue,
    );
  });
}
