import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/config/rider_app_config.dart';
import 'package:movera_rider/features/ride_selection/application/ride_catalog_controller.dart';
import 'package:movera_rider/features/ride_selection/data/ride_selection_repository.dart';

/// Contract v0.7.1 (owner Pricing decisions 2026-10-27): the admin writes
/// each car type's sub-line in sv / fr / en (Manage categories) and the
/// rider app shows it under the name; the rider never chooses seats.
void main() {
  final config = RiderAppConfig.fromJson({
    'version': 7,
    'currency': 'SEK',
    'catalog': {
      'categories': [
        {
          'id': 'xl',
          'label': 'Movera XL',
          'seats': 6,
          'sort': 4,
          'line': {
            'sv': 'Upp till 6 personer',
            'fr': 'Jusqu’à 6 personnes',
            'en': 'Up to 6 people',
          },
        },
        {
          'id': 'child_seat',
          'label': 'Child Seat',
          'seats': 4,
          'sort': 7,
          'line': {
            'sv': 'Bil med babystol eller barnstol',
            'fr': 'Voiture avec siège bébé ou enfant',
            'en': 'Car with a baby or child seat',
          },
        },
        {'id': 'economy', 'label': 'Movera', 'seats': 4, 'sort': 0},
        {
          'id': 'comfort',
          'label': 'Comfort',
          'seats': 4,
          'sort': 1,
          'line': {'sv': '  ', 'en': 'Newer cars, more room', 'fr': 7},
        },
      ],
    },
  })!;

  test('the published catalog carries each sub-line per language', () {
    final byId = {for (final c in config.categories) c.id: c};
    expect(byId['xl']!.line, {
      'sv': 'Upp till 6 personer',
      'fr': 'Jusqu’à 6 personnes',
      'en': 'Up to 6 people',
    });
    expect(byId['economy']!.line, isNull);
    // Blank or not text: left out.
    expect(byId['comfort']!.line, {'en': 'Newer cars, more room'});
  });

  test('the app\'s former kids item is Child Seat (contract v0.6.0)', () {
    final items = RideCatalogController.fromConfig(
      config.categories,
      RideSelectionRepository.builtInRides,
    );
    // The built-in Child Seat item (picture, list price) is used under the
    // admin's name, not an empty one.
    final child = items.firstWhere((i) => i.name == 'Child Seat');
    expect(child.price, greaterThan(0));
    expect(child.image, isNot(RideCatalogJson.fallbackImage));
  });

  test('the car type list shows the sub-line in the rider\'s language', () {
    final items = RideCatalogController.fromConfig(
      config.categories,
      RideSelectionRepository.builtInRides,
    );
    final child = items.firstWhere(
      (i) => i.id == 'kids' || i.id == 'child_seat',
    );
    expect(child.name, 'Child Seat');
    expect(child.lineIn('sv'), 'Bil med babystol eller barnstol');
    expect(child.lineIn('fr'), 'Voiture avec siège bébé ou enfant');
    final economy = items.firstWhere((i) => i.name == 'Movera');
    // No sub-line from the admin: the built-in note stays.
    expect(economy.lineIn('sv'), isNull);
    final comfort = items.firstWhere((i) => i.name == 'Comfort');
    expect(comfort.lineIn('sv'), isNull);
    expect(comfort.lineIn('en'), 'Newer cars, more room');
  });
}
