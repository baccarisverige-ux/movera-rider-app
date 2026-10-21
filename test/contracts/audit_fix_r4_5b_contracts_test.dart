import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/config/rider_app_config.dart';
import 'package:movera_rider/core/config/rider_zones.dart';
import 'package:movera_rider/core/config/trip_zone_config.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/core/location/location_repository.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/auth/application/user_data_wipe.dart';
import 'package:movera_rider/features/history/data/ride_history_repositories.dart';
import 'package:movera_rider/features/ride_booking/data/ride_projection.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _sek(int minor) => {'amountMinor': minor, 'currency': 'SEK'};

/// openapi `TripProjection.required`, read from the shipped contract copy.
List<String> _tripProjectionRequired() {
  final lines = utf8
      .decode(File('contracts/openapi.yaml').readAsBytesSync())
      .split('\n');
  final start = lines.indexOf('    TripProjection:');
  final out = <String>[];
  for (final line in lines.skip(lines.indexOf('      required:', start) + 1)) {
    if (!line.startsWith('      - ')) break;
    out.add(line.substring(8).trim());
  }
  return out;
}

/// A trip exactly as openapi `TripProjection` names it (no legacy keys).
Map<String, dynamic> _contractTrip(String id) => {
  'tripId': id,
  'status': 'completed',
  'version': 7,
  'sequence': 7,
  'kind': 'live',
  'createdAt': '2026-10-20T08:00:00Z',
  'updatedAt': '2026-10-20T08:30:00Z',
  'riderId': 'rdr_1',
  'zoneId': 'Z001',
  'categoryId': 'xl',
  'pickup': {'address': 'Stockholm Central', 'lat': 59.3293, 'lng': 18.0686},
  'dropoff': {'address': 'Arlanda', 'lat': 59.6498, 'lng': 17.9238},
  'stops': const [],
  'fare': _sek(45900),
  'paymentMethod': 'card',
  'ratingStatus': 'pending',
  'pinRequired': false,
};

/// Audit round 4, batch 5b-R2: rider config and the trip projection read
/// the way the contract writes them.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('rider config', () {
    test('rider-r4-3: a waiting block missing one field keeps the others',
        () {
      final waiting = RiderAppConfig.fromJson({
        'version': 14,
        'currency': 'SEK',
        'waiting': {
          'freeWaitMin': 3,
          'perMin': _sek(700),
          'noShowFee': _sek(6000),
        },
      }, fallback: SeedRiderConfigRepository.seed)!.waiting!;
      expect(waiting.freeWaitMin, 3);
      expect(waiting.noShowAfterMin, 3, reason: 'Q41: = freeWaitMin');
      expect(waiting.perMin, const Money(700));
      expect(waiting.noShowFee, const Money(6000));
    });

    test('rider-r4-18: a free rule past its window has no minutes left', () {
      final config = RiderAppConfig.fromJson({
        'version': 14,
        'currency': 'SEK',
        'cancelFees': {
          'live': {
            'economy': {'freeMin': 2, 'type': 'fixed', 'value': 0},
          },
        },
      }, fallback: SeedRiderConfigRepository.seed)!;
      final accepted = DateTime.utc(2026, 10, 21, 8);
      final preview = LiveCancelFeePreview.of(
        config,
        categoryId: 'economy',
        fare: const Money(25900),
        acceptedAt: accepted,
        now: accepted.add(const Duration(minutes: 10)),
      )!;
      expect(preview.fee.isPositive, isFalse);
      expect(preview.freeMinutesLeft, 0);
    });

    test('rider-r4-41: the zone outlives sign-out (no position kept)',
        () async {
      await const LocationRepository().saveLastGoodFix(
        const GeoPoint(36.8065, 10.1815),
      );
      await UserDataWipe.run();
      expect(await const LocationRepository().readLastGoodFix(), isNull);
      expect((await currentRiderZone()).id, RiderZones.tunisia.id);
    });
  });

  group('trip projection', () {
    test('rider-r4-1: a contract TripProjection (dropoff: Place) parses', () {
      final snapshot = RideProjection.toSnapshot(_contractTrip('t1'))!;
      expect(snapshot.destinationAddress, 'Arlanda');
      expect(snapshot.destinationLat, 59.6498);
    });

    test('rider-r4-7: History titles a server trip with the catalog label',
        () async {
      final mock = InProcessMockClient()..rides['t1'] = _contractTrip('t1');
      final record = (await ApiRideHistoryRepository(
        api: ApiClient(
          client: mock,
          env: const AppEnv(
            flavor: AppFlavor.demo,
            apiBaseUrl: 'https://api.demo.movera.invalid',
          ),
        ),
      ).loadOnDemand()).single;
      expect(record.categoryName, 'Movera XL');
    });

  });
}
