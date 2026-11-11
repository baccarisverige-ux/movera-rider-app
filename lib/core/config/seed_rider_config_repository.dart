/// The sample (seed) rider config documents the demo ships with, moved out
/// of `rider_app_config.dart` (D13, R10 #18) with no behaviour change.
library;

import 'rider_app_config.dart';
import 'rider_zones.dart';

/// The seed document the app ships with (Stockholm zone). Same values as
/// `contracts/fixtures/config/rider_app_config.json` (a contract test keeps
/// them equal).
class SeedRiderConfigRepository implements RiderConfigRepository {
  const SeedRiderConfigRepository();

  static final RiderAppConfig seed = RiderAppConfig.fromJson(seedDocument)!;

  /// The seed of each zone the app knows (`RiderZones`): Stockholm's
  /// [seedDocument], and Paris Centre and Tunis Centre with their own
  /// currency, waiting and cancel fees as Admin exports them
  /// (`test/fixtures/admin_config/rider_app_config.<zone>.json`; a test
  /// keeps them equal).
  static final Map<String, RiderAppConfig> zoneSeeds = {
    seed.zoneId: seed,
    for (final overrides in [_franceOverrides, _tunisiaOverrides])
      overrides['zoneId'] as String: RiderAppConfig.fromJson({
        ...seedDocument,
        ...overrides,
      })!,
  };

  /// The seed of [zoneId]; for another zone of the server's list
  /// (v0.11.0 §21) the seed in that zone's currency; else Stockholm's.
  static RiderAppConfig seedFor(String? zoneId) =>
      zoneSeeds[zoneId] ??
      seedForCurrency(RiderZones.byId(zoneId)?.currency ?? '') ??
      seed;

  /// The seed whose prices are in [currency], or null.
  static RiderAppConfig? seedForCurrency(String currency) {
    for (final config in zoneSeeds.values) {
      if (config.currency == currency) return config;
    }
    return null;
  }

  @override
  Future<RiderAppConfig> current() async => seed;

  @override
  Future<RiderAppConfig> forZone(String zoneId) async => seedFor(zoneId);

  static const Map<String, Object?> _franceOverrides = {
    'zoneId': 'FR-PC',
    'currency': 'EUR',
    'country': 'FR',
    'languages': {
      'available': ['en', 'fr', 'sv'],
      'default': {'rider': 'fr', 'driver': 'fr', 'admin': 'fr'},
    },
    'timeZone': 'Europe/Paris',
    'waiting': {
      'freeWaitMin': 5,
      'perMin': {'amountMinor': 115, 'currency': 'EUR'},
      'noShowAfterMin': 5,
      'noShowFee': {'amountMinor': 615, 'currency': 'EUR'},
    },
    'cancelFees': {
      'live': {
        'economy': {
          'freeMin': 2,
          'type': 'fixed',
          'value': 335,
          'min': null,
          'max': null,
        },
        'comfort': {
          'freeMin': 2,
          'type': 'fixed',
          'value': 430,
          'min': null,
          'max': null,
        },
        'premium': {
          'freeMin': 3,
          'type': 'percent',
          'value': 15,
          'min': {'amountMinor': 475, 'currency': 'EUR'},
          'max': {'amountMinor': 1425, 'currency': 'EUR'},
        },
        'priority': {
          'freeMin': 2,
          'type': 'fixed',
          'value': 335,
          'min': null,
          'max': null,
        },
        'xl': {
          'freeMin': 3,
          'type': 'percent',
          'value': 15,
          'min': {'amountMinor': 475, 'currency': 'EUR'},
          'max': {'amountMinor': 1425, 'currency': 'EUR'},
        },
        'electric': {
          'freeMin': 2,
          'type': 'fixed',
          'value': 335,
          'min': null,
          'max': null,
        },
        'pet': {
          'freeMin': 2,
          'type': 'fixed',
          'value': 335,
          'min': null,
          'max': null,
        },
        'child_seat': {
          'freeMin': 2,
          'type': 'fixed',
          'value': 335,
          'min': null,
          'max': null,
        },
      },
      'reservation': {
        'economy': {
          'freeMin': 60,
          'type': 'fixed',
          'value': 475,
          'min': null,
          'max': null,
        },
        'comfort': {
          'freeMin': 60,
          'type': 'fixed',
          'value': 570,
          'min': null,
          'max': null,
        },
        'premium': {
          'freeMin': 120,
          'type': 'percent',
          'value': 25,
          'min': {'amountMinor': 760, 'currency': 'EUR'},
          'max': {'amountMinor': 2850, 'currency': 'EUR'},
        },
        'priority': {
          'freeMin': 60,
          'type': 'fixed',
          'value': 475,
          'min': null,
          'max': null,
        },
        'xl': {
          'freeMin': 120,
          'type': 'percent',
          'value': 25,
          'min': {'amountMinor': 760, 'currency': 'EUR'},
          'max': {'amountMinor': 2850, 'currency': 'EUR'},
        },
        'electric': {
          'freeMin': 60,
          'type': 'fixed',
          'value': 475,
          'min': null,
          'max': null,
        },
        'pet': {
          'freeMin': 60,
          'type': 'fixed',
          'value': 475,
          'min': null,
          'max': null,
        },
        'child_seat': {
          'freeMin': 60,
          'type': 'fixed',
          'value': 475,
          'min': null,
          'max': null,
        },
      },
    },
  };

  static const Map<String, Object?> _tunisiaOverrides = {
    'zoneId': 'TN-TC',
    'currency': 'TND',
    'country': 'TN',
    'languages': {
      'available': ['en', 'fr', 'sv'],
      'default': {'rider': 'fr', 'driver': 'fr', 'admin': 'fr'},
    },
    'timeZone': 'Africa/Tunis',
    'waiting': {
      'freeWaitMin': 5,
      'perMin': {'amountMinor': 3700, 'currency': 'TND'},
      'noShowAfterMin': 5,
      'noShowFee': {'amountMinor': 19500, 'currency': 'TND'},
    },
    'cancelFees': {
      'live': {
        'economy': {
          'freeMin': 2,
          'type': 'fixed',
          'value': 10500,
          'min': null,
          'max': null,
        },
        'comfort': {
          'freeMin': 2,
          'type': 'fixed',
          'value': 13500,
          'min': null,
          'max': null,
        },
        'premium': {
          'freeMin': 3,
          'type': 'percent',
          'value': 15,
          'min': {'amountMinor': 15000, 'currency': 'TND'},
          'max': {'amountMinor': 45000, 'currency': 'TND'},
        },
        'priority': {
          'freeMin': 2,
          'type': 'fixed',
          'value': 10500,
          'min': null,
          'max': null,
        },
        'xl': {
          'freeMin': 3,
          'type': 'percent',
          'value': 15,
          'min': {'amountMinor': 15000, 'currency': 'TND'},
          'max': {'amountMinor': 45000, 'currency': 'TND'},
        },
        'electric': {
          'freeMin': 2,
          'type': 'fixed',
          'value': 10500,
          'min': null,
          'max': null,
        },
        'pet': {
          'freeMin': 2,
          'type': 'fixed',
          'value': 10500,
          'min': null,
          'max': null,
        },
        'child_seat': {
          'freeMin': 2,
          'type': 'fixed',
          'value': 10500,
          'min': null,
          'max': null,
        },
      },
      'reservation': {
        'economy': {
          'freeMin': 60,
          'type': 'fixed',
          'value': 15000,
          'min': null,
          'max': null,
        },
        'comfort': {
          'freeMin': 60,
          'type': 'fixed',
          'value': 18000,
          'min': null,
          'max': null,
        },
        'premium': {
          'freeMin': 120,
          'type': 'percent',
          'value': 25,
          'min': {'amountMinor': 24000, 'currency': 'TND'},
          'max': {'amountMinor': 90000, 'currency': 'TND'},
        },
        'priority': {
          'freeMin': 60,
          'type': 'fixed',
          'value': 15000,
          'min': null,
          'max': null,
        },
        'xl': {
          'freeMin': 120,
          'type': 'percent',
          'value': 25,
          'min': {'amountMinor': 24000, 'currency': 'TND'},
          'max': {'amountMinor': 90000, 'currency': 'TND'},
        },
        'electric': {
          'freeMin': 60,
          'type': 'fixed',
          'value': 15000,
          'min': null,
          'max': null,
        },
        'pet': {
          'freeMin': 60,
          'type': 'fixed',
          'value': 15000,
          'min': null,
          'max': null,
        },
        'child_seat': {
          'freeMin': 60,
          'type': 'fixed',
          'value': 15000,
          'min': null,
          'max': null,
        },
      },
    },
  };

  static const Map<String, Object?> seedDocument = {
    'version': 12,
    'publishedAt': '2026-10-19T08:00:00Z',
    'zoneId': 'Z001',
    'currency': 'SEK',
    'timeZone': 'Europe/Stockholm',
    'country': 'SE',
    'languages': {
      'available': ['en', 'fr', 'sv'],
      'default': {'rider': 'sv', 'driver': 'sv', 'admin': 'sv'},
    },
    'catalog': {
      'categories': [
        {'id': 'economy', 'label': 'Movera', 'seats': 4, 'sort': 1},
        {'id': 'comfort', 'label': 'Comfort', 'seats': 4, 'sort': 2},
        {'id': 'premium', 'label': 'Premium', 'seats': 4, 'sort': 3},
        {'id': 'xl', 'label': 'Movera XL', 'seats': 6, 'sort': 4},
        {'id': 'electric', 'label': 'Electric', 'seats': 4, 'sort': 5},
      ],
    },
    'features': {
      'scheduledRides': true,
      'wallet': true,
      'pin': false,
      'shareTrip': true,
    },
    'paymentMethods': ['cash', 'card', 'apple_pay'],
    'wallet': {'usedFirst': true},
    'tips': [
      {
        'amount': {'amountMinor': 1000, 'currency': 'SEK'},
        'enabled': true,
      },
      {
        'amount': {'amountMinor': 2000, 'currency': 'SEK'},
        'enabled': true,
      },
      {
        'amount': {'amountMinor': 3000, 'currency': 'SEK'},
        'enabled': true,
      },
    ],
    'raiseSteps': [
      {
        'amount': {'amountMinor': 5000, 'currency': 'SEK'},
        'enabled': true,
      },
      {
        'amount': {'amountMinor': 10000, 'currency': 'SEK'},
        'enabled': true,
      },
      {
        'amount': {'amountMinor': 15000, 'currency': 'SEK'},
        'enabled': true,
      },
      {
        'amount': {'amountMinor': 20000, 'currency': 'SEK'},
        'enabled': true,
      },
    ],
    'promoCap': null,
    'booking': {
      'maxStops': 3,
      'bookingHorizonDays': 14,
      'maxPickupMoveMeters': 200,
      // v0.18.17 Book later (owner Q1, Q6).
      'minAheadMin': 15,
      'maxAheadDays': 90,
      'freeChangeBeforeMin': 60,
    },
    'waiting': {
      'freeWaitMin': 5,
      'perMin': {'amountMinor': 1226, 'currency': 'SEK'},
      'noShowAfterMin': 5,
      'noShowFee': {'amountMinor': 6500, 'currency': 'SEK'},
      'byCategory': {
        'economy': {
          'freeWaitMin': 5,
          'perMin': {'amountMinor': 1226, 'currency': 'SEK'},
          'noShowAfterMin': 5,
          'noShowFee': {'amountMinor': 6500, 'currency': 'SEK'},
        },
        'comfort': {
          'freeWaitMin': 5,
          'perMin': {'amountMinor': 1226, 'currency': 'SEK'},
          'noShowAfterMin': 5,
          'noShowFee': {'amountMinor': 6500, 'currency': 'SEK'},
        },
        'premium': {
          'freeWaitMin': 5,
          'perMin': {'amountMinor': 1690, 'currency': 'SEK'},
          'noShowAfterMin': 5,
          'noShowFee': {'amountMinor': 6500, 'currency': 'SEK'},
        },
        'xl': {
          'freeWaitMin': 3,
          'perMin': {'amountMinor': 1226, 'currency': 'SEK'},
          'noShowAfterMin': 3,
          'noShowFee': {'amountMinor': 6500, 'currency': 'SEK'},
        },
        'electric': {
          'freeWaitMin': 5,
          'perMin': {'amountMinor': 1226, 'currency': 'SEK'},
          'noShowAfterMin': 5,
          'noShowFee': {'amountMinor': 6500, 'currency': 'SEK'},
        },
      },
    },
    'cancelReasons': [
      {'code': 'pickup_incorrect', 'title': 'Pickup point is incorrect'},
      {'code': 'plans_changed', 'title': 'Plans changed'},
      {'code': 'something_else', 'title': 'Something else'},
    ],
    'rideCheck': {
      'on': true,
      'stopMinutes': 2,
      'offRouteKm': 2,
      'endFarMeters': 500,
      'noAnswerSeconds': 120,
      'repeatMinutes': 10,
      'noAnswerAlarm': false,
    },
    'routeChange': {
      'on': true,
      'driverCanRefuse': true,
      'answerSeconds': 60,
      'beforePickup': true,
      'fixedPriceTrips': 'block',
    },
    'appUpdate': {'minimumVersion': '1.0.0', 'latestVersion': '1.2.0'},
    'cancelFees': {
      'live': {
        'economy': {
          'freeMin': 2,
          'type': 'fixed',
          'value': 3500,
          'min': null,
          'max': null,
        },
        'comfort': {
          'freeMin': 2,
          'type': 'fixed',
          'value': 4500,
          'min': null,
          'max': null,
        },
        'premium': {
          'freeMin': 3,
          'type': 'percent',
          'value': 15,
          'min': {'amountMinor': 5000, 'currency': 'SEK'},
          'max': {'amountMinor': 15000, 'currency': 'SEK'},
        },
        'xl': {
          'freeMin': 3,
          'type': 'percent',
          'value': 15,
          'min': {'amountMinor': 5000, 'currency': 'SEK'},
          'max': {'amountMinor': 15000, 'currency': 'SEK'},
        },
        'electric': {
          'freeMin': 2,
          'type': 'fixed',
          'value': 3500,
          'min': null,
          'max': null,
        },
      },
      'reservation': {
        'economy': {
          'freeMin': 60,
          'type': 'fixed',
          'value': 5000,
          'min': null,
          'max': null,
        },
        'comfort': {
          'freeMin': 60,
          'type': 'fixed',
          'value': 6000,
          'min': null,
          'max': null,
        },
        'premium': {
          'freeMin': 120,
          'type': 'percent',
          'value': 25,
          'min': {'amountMinor': 8000, 'currency': 'SEK'},
          'max': {'amountMinor': 30000, 'currency': 'SEK'},
        },
        'xl': {
          'freeMin': 120,
          'type': 'percent',
          'value': 25,
          'min': {'amountMinor': 8000, 'currency': 'SEK'},
          'max': {'amountMinor': 30000, 'currency': 'SEK'},
        },
        'electric': {
          'freeMin': 60,
          'type': 'fixed',
          'value': 5000,
          'min': null,
          'max': null,
        },
      },
    },
    'raisePrice': {'maxFactor': 2},
  };
}
