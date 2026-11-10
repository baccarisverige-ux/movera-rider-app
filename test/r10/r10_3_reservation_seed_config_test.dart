// Owner 2026-11-10 (R10, global plan step 73). Was a proof that failed
// before the fix because the reservation controller is built with the
// sample document (`di.dart:245` `config: SeedRiderConfigRepository.seed`)
// and loads with `current()` (`di.dart:246`), which returns the sample when
// the server cannot be read (`api_rider_config_repository.dart:117-119,
// 181-195`). `reservation_controller.dart:136-143` then uses it for a SEK
// booked ride before the LiveDataOnly guard. AUDIT-R10 §3.2 items 2-3, R10 #3.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/config/api_rider_config_repository.dart';
import 'package:movera_rider/core/config/live_data_only.dart';
import 'package:movera_rider/core/feature_flags/feature_flags.dart';
import 'package:movera_rider/core/config/rider_app_config.dart';
import 'package:movera_rider/core/config/rider_zones.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/domain/reservation_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _pickup = DateTime.utc(2026, 10, 20, 12);

Reservation _premiumRide() => Reservation(
  reservationId: 'r-premium',
  createdAt: DateTime.utc(2026, 10, 19),
  scheduledPickupAt: _pickup,
  pickup: const ReservationPlace(label: 'A'),
  destination: const ReservationPlace(label: 'B'),
  categoryId: 'premium',
  categoryName: 'premium',
  categoryImage: '',
  price: 420,
  currency: 'SEK',
  paymentMethod: 'cash',
  status: ReservationStatus.driverAssigned,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const staging = AppEnv(
    flavor: AppFlavor.staging,
    apiBaseUrl: 'https://api.movera.invalid',
  );

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    RiderZones.useSamples();
    LiveDataOnly.on = true;
    ServerFeatures.clear();
  });
  tearDown(() {
    LiveDataOnly.on = false;
    RiderZones.useSamples();
    ServerFeatures.clear();
  });

  ReservationController liveComposition() {
    // As `di.dart` composes it on the live wire, with the server unreachable.
    final riderConfig = ApiRiderConfigRepository(
      api: ApiClient(
        env: staging,
        client: MockClient((_) async => throw const SocketException('offline')),
      ),
      cache: MemoryRiderConfigCache(),
      homeZoneId: 'Z001',
    );
    return ReservationController(
      environment: staging,
      configLoader: riderConfig.currentServed,
    );
  }

  final seedRule = SeedRiderConfigRepository.seed.reservationFeeFor('premium');
  final at = _pickup.subtract(const Duration(minutes: 90));

  test('live, before any load: no sample fee on the cancel terms', () {
    final terms = liveComposition().cancelTermsFor(_premiumRide(), now: at);
    expect(
      terms.window,
      isNot(Duration(minutes: seedRule!.freeMin)),
      reason: 'the free window came from the sample premium rule',
    );
    expect(
      terms.fee?.amountMinor,
      isNot(10500),
      reason: 'the sample premium fee (25% of 420 kr) is shown on live',
    );
  });

  test('live, server unreachable after refresh: still no sample fee', () async {
    final controller = liveComposition();
    await controller.refreshRules();
    final terms = controller.cancelTermsFor(_premiumRide(), now: at);
    expect(
      terms.fee?.amountMinor,
      isNot(10500),
      reason:
          'current() returned the sample document on live and the cancel '
          'sheet shows its premium fee',
    );
  });
}
