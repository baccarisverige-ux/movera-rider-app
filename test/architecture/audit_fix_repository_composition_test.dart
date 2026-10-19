import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/app/config/repository_composition.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/contracts/repository_authority.dart';
import 'package:movera_rider/core/observability/observability.dart';
import 'package:movera_rider/core/payments/api_payment_gateway.dart';
import 'package:movera_rider/core/payments/payment_gateway.dart';
import 'package:movera_rider/features/history/data/ride_history_repositories.dart';
import 'package:movera_rider/features/payments/data/default_payment_store.dart';
import 'package:movera_rider/features/payments/data/local_payment_repository.dart';
import 'package:movera_rider/features/payments/data/saved_cards_store.dart';
import 'package:movera_rider/features/profile/data/profile_repository.dart';
import 'package:movera_rider/features/reservations/data/local_reservation_repository.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/domain/reservation_errors.dart';
import 'package:movera_rider/features/ride_booking/data/active_trip_repositories.dart';
import 'package:movera_rider/features/wallet/application/wallet_controller.dart';
import 'package:movera_rider/features/wallet/data/wallet_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _CountingGateway implements PaymentGateway {
  int creates = 0;

  @override
  Future<PaymentIntent> create({
    required int amountMinor,
    required String currency,
    required String idempotencyKey,
    PaymentPurpose? purpose,
    String? rideId,
  }) async {
    creates++;
    return PaymentIntent(
      id: 'pi_1',
      amountMinor: amountMinor,
      currency: currency,
    );
  }

  @override
  Future<String> confirm(String intentId) async => 'succeeded';

  @override
  Future<String> status(String intentId) async => 'succeeded';
}

/// ARCH-6 / ARCH-7: release composition never exposes a device-only rider
/// repository; features without a server side are off and fail closed.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(Observability.reset);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const production = AppEnv(
    flavor: AppFlavor.production,
    apiBaseUrl: 'https://api.movera.example',
  );
  const staging = AppEnv(
    flavor: AppFlavor.staging,
    apiBaseUrl: 'https://api.staging.movera.example',
  );
  const demo = AppEnv(
    flavor: AppFlavor.demo,
    apiBaseUrl: 'https://api.demo.movera.invalid',
  );

  test('production composition holds no device-only rider repository', () {
    for (final env in [production, staging]) {
      final scope = AppScope.composeForEnvironment(env);
      addTearDown(scope.disposeForTest);

      expect(scope.flags.wallet, isFalse);
      expect(scope.flags.scheduledRides, isFalse);
      expect(scope.flags.bookingLater, isFalse);
      expect(scope.flags.savedCards, isFalse);

      expect(scope.walletBalances, isNot(isA<LocalWalletRepository>()));
      expect(scope.walletBalances, isA<FeatureOffRepository>());
      expect(
        scope.reservationRepository,
        isNot(isA<LocalReservationRepository>()),
      );
      expect(scope.reservationRepository, isA<FeatureOffRepository>());
      expect(scope.savedCardsStore, isNot(isA<PrefsSavedCardsStore>()));
      expect(scope.savedCardsStore, isA<FeatureOffRepository>());

      for (final serverBacked in <Object>[
        scope.payments,
        scope.defaultPayment,
        scope.rideHistory,
        scope.activeTrips,
        scope.profile.repository,
      ]) {
        expect(serverBacked, isA<ServerBackedRepository>());
      }
      expect(scope.payments, isNot(isA<LocalPaymentRepository>()));
      expect(scope.defaultPayment, isNot(isA<PrefsDefaultPaymentStore>()));
      expect(scope.profile.repository, isNot(isA<ProfileRepository>()));
    }
  });

  test('demo keeps every device-local feature exactly as before', () {
    final scope = AppScope.composeForEnvironment(demo);
    addTearDown(scope.disposeForTest);
    expect(scope.flags.wallet, isTrue);
    expect(scope.flags.scheduledRides, isTrue);
    expect(scope.flags.savedCards, isTrue);
    expect(scope.walletBalances, isA<LocalWalletRepository>());
    expect(scope.reservationRepository, isA<LocalReservationRepository>());
    expect(scope.savedCardsStore, isA<PrefsSavedCardsStore>());
    expect(scope.payments, isA<LocalPaymentRepository>());
    expect(scope.rideHistory, isA<LocalRideHistoryRepository>());
    expect(scope.activeTrips, isA<DeviceOnlyActiveTripRepository>());
  });

  test('release rejects each device-only repository named in ARCH-7', () {
    final local = <String, Object>{
      'wallet': LocalWalletRepository(),
      'reservations': LocalReservationRepository(),
      'savedCards': const PrefsSavedCardsStore(),
      'paymentMethods': LocalPaymentRepository(),
      'defaultPayment': const PrefsDefaultPaymentStore(),
      'rideHistory': const LocalRideHistoryRepository(),
      'activeTrip': const DeviceOnlyActiveTripRepository(),
      'profile': ProfileRepository(),
    };
    for (final entry in local.entries) {
      for (final enabled in [true, false]) {
        expect(
          () => RepositoryComposition.validate(
            environment: production,
            surfaces: [
              RepositorySurface(
                entry.key,
                implementation: entry.value,
                enabled: enabled,
              ),
            ],
          ),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              allOf(contains('Device-only'), contains(entry.key)),
            ),
          ),
          reason: '${entry.key} enabled=$enabled',
        );
      }
      expect(
        () => RepositoryComposition.validate(
          environment: demo,
          surfaces: [RepositorySurface(entry.key, implementation: entry.value)],
        ),
        returnsNormally,
      );
    }
    // A switched-off feature may not be switched on with its stand-in.
    expect(
      () => RepositoryComposition.validate(
        environment: production,
        surfaces: const [
          RepositorySurface(
            'wallet',
            implementation: DisabledWalletRepository(),
          ),
        ],
      ),
      throwsStateError,
    );
  });

  test('a release wallet top-up never charges the card', () async {
    final scope = AppScope.composeForEnvironment(production);
    addTearDown(scope.disposeForTest);
    final gateway = _CountingGateway();
    final wallet = WalletController(
      gateway: gateway,
      balances: scope.walletBalances,
    );
    final outcome = await wallet.topUp(previous: 0, amount: 100);
    expect(outcome, isA<TopUpNotCharged>());
    expect(gateway.creates, 0);
    expect(await wallet.loadBalance(), 0);
  });

  test('a release Book for later stores nothing on the device', () async {
    final scope = AppScope.composeForEnvironment(production);
    addTearDown(scope.disposeForTest);
    await expectLater(
      scope.reservations.create(
        ReservationDraft(
          scheduledPickupAt: DateTime.now().add(const Duration(hours: 3)),
          pickup: const ReservationPlace(label: 'A', lat: 59.3, lng: 18.0),
          destination: const ReservationPlace(label: 'B', lat: 59.6, lng: 17.9),
          categoryId: 'economy',
          categoryName: 'Movera',
          categoryImage: 'assets/images/rides/movera.webp',
          price: 259,
          paymentMethod: 'Pay in car',
        ),
      ),
      throwsA(isA<ReservationsUnavailableException>()),
    );
    expect(scope.reservations.all, isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(PrefsReservationStorage.key), isNull);
  });

  test('a release saved card is refused and not listed', () async {
    final scope = AppScope.composeForEnvironment(production);
    addTearDown(scope.disposeForTest);
    await expectLater(
      scope.savedCards.add(
        number: '4242424242424242',
        expMonth: 12,
        expYear: DateTime.now().year + 2,
        holder: 'Test Rider',
      ),
      throwsUnsupportedError,
    );
    expect(scope.savedCards.list(), isEmpty);
  });

  test('a wallet top-up intent says it is a wallet top-up', () async {
    final mock = InProcessMockClient();
    final gateway = ApiPaymentGateway(
      api: ApiClient(client: mock, env: demo),
    );
    final wallet = WalletController(
      gateway: gateway,
      balances: LocalWalletRepository(_MemoryBalance()),
    );
    final outcome = await wallet.topUp(previous: 0, amount: 50);
    expect(outcome, isA<TopUpCredited>());
    expect(mock.paymentIntents.values.single['purpose'], 'wallet_topup');
  });
}

class _MemoryBalance implements WalletBalanceSource {
  double value = 0;

  @override
  Future<double> loadBalance() async => value;

  @override
  Future<void> saveBalance(double next) async => value = next;
}
