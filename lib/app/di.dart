import 'package:movera_rider/core/config/rider_app_config.dart';
import 'package:movera_rider/features/promotions/application/rider_promotion_controller.dart';
import 'package:movera_rider/app/lifecycle/app_lifecycle.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/app/config/pin_composition.dart';
import 'package:movera_rider/app/config/repository_composition.dart';
import 'package:movera_rider/app/config/transport_composition.dart';
import 'package:movera_rider/app/config/auth_composition.dart';
import 'package:movera_rider/app/config/wallet_composition.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/auth/secure_token_store.dart';
import 'package:movera_rider/core/auth/token_store.dart';
import 'package:movera_rider/core/contracts/repository_authority.dart';
import 'package:movera_rider/core/feature_flags/feature_flags.dart';
import 'package:movera_rider/core/location/app_geocoding.dart';
import 'package:movera_rider/core/location/location_repository.dart';
import 'package:movera_rider/core/location/place_search.dart';
import 'package:movera_rider/core/logging/crash_reporter.dart';
import 'package:movera_rider/core/maps/google_map_provider.dart';
import 'package:movera_rider/core/maps/map_camera_controller.dart';
import 'package:movera_rider/core/maps/map_facade.dart';
import 'package:movera_rider/core/maps/map_lifecycle.dart';
import 'package:movera_rider/core/maps/marker_store.dart';
import 'package:movera_rider/core/maps/routing_service.dart';
import 'package:movera_rider/core/motion/motion_engine.dart';
import 'package:movera_rider/core/notifications/push_permission_gate.dart';
import 'package:movera_rider/core/notifications/firebase_push_service.dart';
import 'package:movera_rider/core/notifications/push_service.dart';
import 'package:movera_rider/core/observability/http_observability.dart';
import 'package:movera_rider/core/observability/observability.dart';
import 'package:movera_rider/core/payments/api_payment_gateway.dart';
import 'package:movera_rider/core/payments/mock_payment_gateway.dart';
import 'package:movera_rider/core/payments/payment_gateway.dart';
import 'package:movera_rider/core/permissions/permission_service.dart';
import 'package:movera_rider/core/realtime/api_ride_realtime.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/core/realtime/realtime_connection.dart';
import 'package:movera_rider/core/realtime/ride_realtime.dart';
import 'package:movera_rider/core/sockets/socket_client.dart';
import 'package:movera_rider/features/auth/application/auth_controller.dart';
import 'package:movera_rider/features/booking/application/booking_coordinator.dart';
import 'package:movera_rider/features/destination/application/destination_controller.dart';
import 'package:movera_rider/features/destination/application/destination_session.dart';
import 'package:movera_rider/features/destination_search/application/destination_search_controller.dart';
import 'package:movera_rider/features/onboarding/application/onboarding_controller.dart';
import 'package:movera_rider/features/history/data/ride_history_repositories.dart';
import 'package:movera_rider/features/history/domain/ride_history_repository.dart';
import 'package:movera_rider/features/messages/data/api_trip_messages.dart';
import 'package:movera_rider/features/messages/domain/trip_messages_transport.dart';
import 'package:movera_rider/features/payments/application/saved_cards_controller.dart';
import 'package:movera_rider/features/payments/data/api_payment_method_repository.dart';
import 'package:movera_rider/features/payments/data/default_payment_store.dart';
import 'package:movera_rider/features/payments/data/local_payment_repository.dart';
import 'package:movera_rider/features/payments/data/saved_cards_store.dart';
import 'package:movera_rider/features/payments/domain/payment_repository.dart';
import 'package:movera_rider/features/pickup/application/pickup_session.dart';
import 'package:movera_rider/features/pickup/application/pickup_spots_controller.dart';
import 'package:movera_rider/features/profile/application/account_security_controller.dart';
import 'package:movera_rider/features/profile/application/app_language_controller.dart';
import 'package:movera_rider/features/profile/application/profile_controller.dart';
import 'package:movera_rider/features/profile/data/account_security_repository.dart';
import 'package:movera_rider/features/profile/data/synced_profile_repository.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/data/api_scheduled_ride_rules_source.dart';
import 'package:movera_rider/features/reservations/data/disabled_reservation_repository.dart';
import 'package:movera_rider/features/reservations/data/local_reservation_repository.dart';
import 'package:movera_rider/features/reservations/data/mock_reservation_dispatch.dart';
import 'package:movera_rider/features/reservations/domain/reservation_repository.dart';
import 'package:movera_rider/features/ride_booking/application/ride_session.dart';
import 'package:movera_rider/features/ride_booking/data/active_trip_repositories.dart';
import 'package:movera_rider/features/ride_booking/domain/active_trip_repository.dart';
import 'package:movera_rider/features/ride_booking/data/api_quote_repository.dart';
import 'package:movera_rider/features/ride_booking/data/mock_quote_repository.dart';
import 'package:movera_rider/features/ride_complete/application/ride_complete_controller.dart';
import 'package:movera_rider/features/ride_selection/application/ride_catalog_controller.dart';
import 'package:movera_rider/features/ride_selection/data/ride_selection_repository.dart';
import 'package:movera_rider/features/safety/application/emergency_call_service.dart';
import 'package:movera_rider/features/safety/application/safety_controller.dart';
import 'package:movera_rider/features/saved_places/application/saved_places_controller.dart';
import 'package:movera_rider/features/support/application/support_controller.dart';
import 'package:movera_rider/features/wallet/application/wallet_controller.dart';
import 'package:movera_rider/features/wallet/data/wallet_repository.dart';
import 'package:movera_rider/features/wallet/domain/wallet_ledger.dart';

class AppScope {
  AppScope._(this.environment)
      : flags = FeatureFlags.forEnvironment(environment),
        maps = GoogleMapProvider(),
        mapLifecycle = MapLifecycleController(),
        markers = MarkerStore(),
        motion = MotionEngine(),
        ride = RideSession(),
        tokens = SecureTokenStore(),
        realtime = RealtimeConnection(),
        wallet = WalletLedger(),
        lifecycle = AppLifecycleObserver(),
        permissions = PermissionService(),
        search = PlaceSearchService(),
        location = LocationRepository(),
        crashes = const CrashReporter(),
        pickup = PickupSession(),
        destination = DestinationSession(),
        booking = BookingCoordinator() {
    api = ApiClient(
      env: environment,
      tokens: tokens,
      onSessionExpired: () async {
        // The live ride snapshot is deliberately kept: the ride goes on
        // server-side, and after the rider signs back in enterMoveraApp
        // resumes it and the server re-validates it. The rider's other
        // data stays too: the same rider usually signs back in, and when a
        // different one does, AuthController wipes it first
        // (UserDataWipe.enterSessionAs). Sign-out wipes everything.
        await LocationRepository.clearLastGoodFix();
        // rider-u201: the microphone does not stay on behind Sign in.
        await SafetyController.stopRecordingForSessionExpiry();
        // Sign in becomes the root gate's child so the gate survives. The
        // screen is registered from app.dart so DI never imports
        // presentation (ARCH-17).
        AppScope.showSignInOnSessionExpired?.call();
      },
    );
    paymentGateway = environment.allowsMockTransport
        ? MockPaymentGateway()
        : ApiPaymentGateway(api: api);
    push = environment.allowsMockTransport
        ? NoopPushService()
        : FirebasePushService(api: api, environment: environment);

    if (environment.isReleaseLike) {
      final sink = HttpObservabilitySink(baseUrl: environment.apiBaseUrl);
      observabilitySink = sink;
      Observability.configure(
        loggerSink: sink,
        analyticsSink: sink,
        crashSink: sink,
      );
    }

    // ARCH-6 / ARCH-7: rider-facing repositories. Demo/dev keep the
    // device-only ones; release builds get the server-backed ones, and a
    // feature with no server side yet is switched off by its flag and gets a
    // fail-closed stand-in. RepositoryComposition below enforces it.
    final release = environment.isReleaseLike;
    walletBalances = flags.wallet || !release
        ? LocalWalletRepository()
        : const DisabledWalletRepository();
    reservationRepository =
        flags.scheduledRides || flags.bookingLater || !release
        ? LocalReservationRepository()
        : DisabledReservationRepository();
    savedCardsStore = flags.savedCards || !release
        ? const PrefsSavedCardsStore()
        : const DisabledSavedCardsStore();
    if (release) {
      final methods = ApiPaymentMethodRepository(api: api);
      payments = methods;
      defaultPayment = methods;
      // rider-r4-7: a server trip names only its categoryId; the
      // catalog the rider sees names it.
      rideHistory = ApiRideHistoryRepository(
        api: api,
        categoryLabel: (id) => catalog.labelOf(id),
      );
      activeTrips = ApiActiveTripRepository(
        api: api,
        categoryLabel: (id) => catalog.labelOf(id),
      );
    } else {
      payments = LocalPaymentRepository();
      defaultPayment = const PrefsDefaultPaymentStore();
      rideHistory = const LocalRideHistoryRepository();
      activeTrips = const DeviceOnlyActiveTripRepository();
    }
    reservations = ReservationController(
      store: reservationRepository,
      environment: environment,
      // Simulated scheduled-ride dispatch: mock-transport builds only.
      mockDispatch: environment.allowsMockTransport
          ? MockReservationDispatch()
          : null,
      // Admin-set cancel window, late fee and driver reveal. Only asked for
      // where Book for later is on.
      rulesSource: flags.scheduledRides || flags.bookingLater
          ? ApiScheduledRideRulesSource(api)
          : null,
      // X3: reservation cancel fees per category from the rider config.
      config: SeedRiderConfigRepository.seed,
      configLoader: () => riderConfig.current(),
    );
    // FLOW-7: the name, language and consents go to the server; the device
    // copy is the cache. With the mock transport the in-process mock
    // answers, so a demo rider sees no difference.
    profile = ProfileController(store: SyncedProfileRepository(api: api));

    accountSecurity = AccountSecurityController(
      repository: AccountSecurityRepository(api: api),
    );

    geocoding = AppGeocoding(
      api: api,
      allowPublicReverseFallback: environment.allowsMockTransport,
    );
    // uat-r1: the demo's in-process transport knows no roads; on the web
    // demo the road line comes from a public router (as reverse geocoding
    // does above). Release builds never reach it.
    routing = RoutingService(
      api: api,
      allowPublicRoadFallback: environment.allowsMockTransport,
    );
    RoutingService.defaultProvider ??= () => AppScope.instance.routing;
    quotes = ApiQuoteRepository(api: api);
    // R-O2: the transports report the trip's projection version, which
    // the rider's commands send back as `expectedVersion`.
    rideRealtime = environment.allowsMockTransport
        ? MockRideRealtime(
            api: api,
            connection: realtime,
            onProjectionVersion: ride.observeProjectionVersion,
          )
        : ApiRideRealtime(
            api: api,
            connection: realtime,
            onProjectionVersion: ride.observeProjectionVersion,
          );
    sockets = SocketClient(realtime);
    camera = MapCameraController(maps);
    destinationSearch = DestinationSearchController(search, api: api);
    map = MapFacade(
      provider: maps,
      camera: camera,
      markers: markers,
      lifecycle: mapLifecycle,
      routing: routing,
    );

    PinComposition.validate(
      environment: environment,
      usesMockPinIssuance: api.usesMockTransport,
    );
    TransportComposition.validate(
      environment: environment,
      api: api,
      realtime: rideRealtime,
      paymentGateway: paymentGateway,
      push: push,
      emergencyDialer: emergencyDialer,
      logger: Observability.logger,
      analytics: Observability.analytics,
      crashes: Observability.crashes,
    );
    AuthComposition.validate(environment);
    WalletComposition.validate(
      environment: environment,
      usesLocalBalanceSource: flags.wallet && walletBalances is! ServerBackedRepository,
    );
    RepositoryComposition.validate(
      environment: environment,
      surfaces: [
        RepositorySurface(
          'wallet',
          implementation: walletBalances,
          enabled: flags.wallet,
        ),
        RepositorySurface(
          'reservations',
          implementation: reservationRepository,
          enabled: flags.scheduledRides || flags.bookingLater,
        ),
        RepositorySurface(
          'savedCards',
          implementation: savedCardsStore,
          enabled: flags.savedCards,
        ),
        RepositorySurface('paymentMethods', implementation: payments),
        RepositorySurface('defaultPayment', implementation: defaultPayment),
        RepositorySurface('rideHistory', implementation: rideHistory),
        RepositorySurface('activeTrip', implementation: activeTrips),
        RepositorySurface('profile', implementation: profile.repository),
      ],
    );
  }

  static final instance = AppScope._(AppEnv.current);

  /// Navigation to Sign in after a forced sign-out, registered by the app
  /// shell ([registerSessionExpiredNavigation] in app.dart).
  static void Function()? showSignInOnSessionExpired;

  /// Uses the exact production composition root without replacing individual
  /// dependencies by hand. Phase 72 CI exercises this factory directly.
  static AppScope composeForEnvironment(AppEnv environment) =>
      AppScope._(environment);

  final AppEnv environment;
  final GoogleMapProvider maps;
  final MapLifecycleController mapLifecycle;
  final MarkerStore markers;
  late final MapCameraController camera;
  late final MapFacade map;
  final MotionEngine motion;
  final RideSession ride;
  late final ApiClient api;
  final TokenStore tokens;
  final RealtimeConnection realtime;
  late final SocketClient sockets;
  late final QuoteRepository quotes;
  late final PaymentRepository payments;
  late final DefaultPaymentStore defaultPayment;
  late final WalletBalanceRepository walletBalances;
  late final ReservationRepository reservationRepository;

  /// rider-u124: Book for later can book in this build. Off where it is
  /// composed with the fail-closed stand-in (staging/production, flags
  /// off), so its entry points say so at once instead of running the
  /// whole scheduling flow first.
  bool get bookLaterAvailable => reservationRepository is! FeatureOffRepository;
  late final SavedCardsStore savedCardsStore;
  late final RideHistoryRepository rideHistory;
  late final ActiveTripRepository activeTrips;
  late final PaymentGateway paymentGateway;
  final WalletLedger wallet;
  final AppLifecycleObserver lifecycle;
  final PermissionService permissions;
  final PlaceSearchService search;
  final LocationRepository location;
  late final AppGeocoding geocoding;
  late final PushService push;
  final CrashReporter crashes;
  final PickupSession pickup;
  final DestinationSession destination;
  final BookingCoordinator booking;
  late final DestinationSearchController destinationSearch;
  late final RoutingService routing;
  late final RideRealtime rideRealtime;
  late final ReservationController reservations;
  late final ProfileController profile;
  late final AccountSecurityController accountSecurity;

  // Phase 138: these default-construct their own dependencies internally
  // (several read AppScope.instance themselves), so each is declared as a
  // lazy `late final` field initializer rather than built eagerly in the
  // constructor above - AppScope.instance is not yet bound while this
  // constructor is still running, so a screen reading one of these before
  // that assignment completes would otherwise hit it uninitialized. Nothing
  // does that in practice (screens read AppScope.instance.x from their own
  // initState, always after app startup), so this only matters for
  // correctness under construction order, not normal use.
  late final AuthController auth = AuthController();
  late final RideCompleteController rideComplete = RideCompleteController();
  late final WalletController walletController = WalletController(
    balances: walletBalances,
    // rider-u232: the Payments tab's default is the one Select Ride uses.
    defaultPayment: defaultPayment,
  );
  late final SavedPlacesController savedPlaces = SavedPlacesController();

  /// The app language: the rider's choice, else the zone default (Q48).
  late final AppLanguageController language = AppLanguageController();
  late final PickupSpotsController pickupSpots = PickupSpotsController();
  late final SupportController support = SupportController();
  late final OnboardingController onboarding = OnboardingController();
  late final DestinationController destinationMemory = DestinationController();
  late final RideSelectionRepository rideCatalog = RideSelectionRepository();

  /// Ride categories from the server (admin panel), with cache and built-in
  /// fallbacks. Loaded at bootstrap and again when Select Ride opens.
  late final RideCatalogController catalog = RideCatalogController(api: api);

  /// RiderAppConfig (contract v0.3.0 §6): the local seed today,
  /// `GET /rider/config?zoneId` once a backend serves it.
  RiderConfigRepository riderConfig = const SeedRiderConfigRepository();

  /// Demo saved cards (stored on this device until the payment partner's
  /// vault takes over).
  late final SavedCardsController savedCards = SavedCardsController(
    store: savedCardsStore,
  );

  /// Contract v0.5.4: the trip chat (`/trips/{tripId}/messages`) on the
  /// live wire. The demo's mock transport has no chat server, so there it
  /// is null and Chat stays read-only as before.
  late final TripMessagesTransport? tripMessages =
      api.contractWire ? ApiTripMessages(api: api) : null;

  /// The in-app explanation in front of the OS notification prompt.
  late final PushPermissionGate pushPermission = PushPermissionGate(
    push: push,
    enabled: !environment.allowsMockTransport,
  );
  late final RiderPromotionController promotion = RiderPromotionController(
    api,
  );
  HttpObservabilitySink? observabilitySink;
  /// Per flavor (ARCH-6 / ARCH-7): release switches off the features whose
  /// data still lives only on this device.
  FeatureFlags flags;

  EmergencyDialer get emergencyDialer => EmergencyCallService.shared.dialer;

  void disposeForTest() {
    rideRealtime.dispose();
    realtime.dispose();
    observabilitySink?.dispose();
    if (environment.isReleaseLike) Observability.reset();
  }
}
