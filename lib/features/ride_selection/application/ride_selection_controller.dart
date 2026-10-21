import 'package:movera_rider/features/ride_booking/domain/route_stop.dart';
import 'package:movera_rider/core/contracts/category_ids.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';

import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/config/zone_settings.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/core/feature_flags/feature_flags.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/core/performance/performance_budgets.dart';
import 'package:movera_rider/features/fare/application/fare_controller.dart';
import 'package:movera_rider/features/payments/application/card_entry_policy.dart';
import 'package:movera_rider/features/payments/application/saved_cards_controller.dart';
import 'package:movera_rider/features/payments/data/default_payment_store.dart';
import 'package:movera_rider/features/ride_booking/data/mock_quote_repository.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/quote.dart';
import 'package:movera_rider/features/ride_selection/application/ride_catalog_controller.dart';
import 'package:movera_rider/features/ride_selection/data/ride_selection_repository.dart';
import 'package:movera_rider/features/ride_selection/domain/booking_mode.dart';
import 'package:movera_rider/features/ride_selection/domain/ride_selection.dart';
import 'package:movera_rider/features/wallet/domain/wallet_split.dart';
import 'package:movera_rider/l10n/l10n.dart';

class RideSelectionController {
  /// Categories come from [catalog] (the server's list, see
  /// [RideCatalogController]). A test that passes its own [store] gets a
  /// fixed catalog instead; the default is the app's shared controller.
  RideSelectionController({
    RideSelectionRepository? store,
    RideCatalogController? catalog,
    QuoteRepository? quotes,
    FareController? fare,
    FeatureFlags? flags,
    DefaultPaymentStore? paymentStore,
    SavedCardsController? savedCards,
    this.bookingMode = BookingMode.now,
    this.lockBookingMode = false,
    String currency = Money.defaultCurrency,
  }) : _currency = currency,
       _store = store ?? RideSelectionRepository(),
       _catalog = catalog ?? (store == null ? AppScope.instance.catalog : null),
       _quotes = quotes ?? AppScope.instance.quotes,
       _fare = fare ?? FareController(),
       _flags = flags ?? AppScope.instance.flags,
       _paymentStore = paymentStore,
       _savedCards = savedCards ?? AppScope.instance.savedCards {
    _selectDefaultPayment();
  }

  final RideSelectionRepository _store;
  final RideCatalogController? _catalog;
  final QuoteRepository _quotes;
  final FareController _fare;
  final FeatureFlags _flags;
  final DefaultPaymentStore? _paymentStore;
  final SavedCardsController _savedCards;

  /// Q7: the currency of the pickup's zone. Every price below is in whole
  /// units of it. Select Ride sets it from the pickup; a quote the server
  /// prices in another currency moves it (the server decides). A change
  /// drops the prices held in the old currency. The wallet row may come
  /// or go with it (Q8), so the chosen method is kept by brand
  /// (rider-u184).
  String get currency => _currency;
  String _currency;
  set currency(String value) {
    if (value == _currency) return;
    _keepPayment(() {
      _currency = value;
      offeredPrices.clear();
    });
  }

  /// The currency of [walletBalance]: the trip's (Q8: one balance per
  /// currency), once Select Ride has read it.
  String walletCurrency = Money.defaultCurrency;

  /// Whether the wallet can pay this trip: only in its own currency. The
  /// app never converts between currencies.
  bool get walletMatchesTrip => walletCurrency == currency;

  /// Q7 FINAL: the contract payment methods the pickup zone's config
  /// offers (`cash`, `card`, `apple_pay`, `google_pay`). Select Ride sets
  /// it from the zone's config; the wallet is separate.
  List<String> zonePaymentMethods = ZoneDefaults.paymentMethods;

  /// The contract zone method a payment row is ([zonePaymentMethods]), or
  /// null for the wallet (never a zone method).
  static String? zoneMethodOf(String brand) {
    if (brand == 'cash') return 'cash';
    if (brand == 'cards' || brand.startsWith('card')) return 'card';
    if (brand == 'apple') return 'apple_pay';
    if (brand == 'google') return 'google_pay';
    return null;
  }

  /// Whether this build offers the wallet at all.
  bool get walletEnabled => _flags.enableWallet;

  /// [major] whole units of [currency] as Money.
  Money moneyOf(double major) => Money.fromLegacyMajor(major, currency);

  /// [quote]'s total in whole units of its currency.
  static double majorOf(RideQuote quote) =>
      Money(quote.totalMinor, quote.currency).major;

  final Map<String, double> offeredPrices = {};
  final Map<String, String> quoteIds = {};
  final Map<String, DateTime> quoteExpiresAt = {};
  final Map<String, RideQuote> authoritativeQuotes = {};
  final Set<String> unavailableQuoteIds = <String>{};

  /// Rides whose quote ran out: until a new one lands they have no price
  /// to show, and their list price is never taken as the fare
  /// (rider-u185, P4).
  final Set<String> _expiredQuoteIds = <String>{};
  int _quoteGeneration = 0;
  final Set<void Function()> _cancelQuoteTimeouts = <void Function()>{};
  bool _disposed = false;
  bool usedFallback = false;
  String selectedRideId = CategoryIds.economy;
  int selectedPayment = 1;
  DateTime? scheduledFor;
  BookingMode bookingMode;
  bool lockBookingMode;

  bool get isScheduled =>
      bookingMode == BookingMode.scheduled && scheduledFor != null;

  bool get entersFindingDriver => bookingMode.entersFindingDriver;

  bool get createsReservation => bookingMode.createsReservation;

  List<RideCatalogItem> rides() => _catalog?.current ?? _store.rides();

  /// Fires when the catalog changes (a server answer arrived). Null when
  /// the catalog is a fixed store.
  Listenable? get catalogChanges => _catalog;

  /// Re-asks the server for the categories; [rides] updates in place and
  /// [catalogChanges] fires. A fixed store has nothing to refresh.
  Future<void> refreshCatalog() async {
    final catalog = _catalog;
    if (catalog == null) return;
    await catalog.load();
  }

  RideCatalogItem rideById(String id) {
    final catalog = rides();
    if (catalog.isEmpty) {
      throw StateError('ride catalog is empty');
    }
    for (final ride in catalog) {
      if (ride.id == id) return ride;
    }
    return catalog.first;
  }

  RideCatalogItem? rideByIdOrNull(String id) {
    for (final ride in rides()) {
      if (ride.id == id) return ride;
    }
    return null;
  }

  RideCatalogItem? ensureCatalogSelection() {
    final catalog = rides();
    if (catalog.isEmpty) return null;
    final current = rideByIdOrNull(selectedRideId);
    if (current != null) return current;
    final fallback = catalog.first;
    selectedRideId = fallback.id;
    if (fallback.currency == currency &&
        !_expiredQuoteIds.contains(fallback.id)) {
      offeredPrices.putIfAbsent(fallback.id, () => fallback.price);
    }
    return fallback;
  }

  /// Movera Wallet balance in whole units of [walletCurrency], once known.
  /// The wallet is only offered when there is money in it.
  double walletBalance = 0;

  /// "Use wallet balance first": the balance is taken off the fare before
  /// the chosen method pays the rest. On by default.
  bool useWalletFirst = true;

  /// The part of [priceKr] the wallet covers for the current payment
  /// choice, or 0. Paying the whole ride from the wallet is its own method
  /// and is not a split.
  /// [priceKr] is in whole units of [currency].
  double walletAppliedKr(double priceKr) =>
      Money(walletSplitFor(moneyOf(priceKr).amountMinor).walletMinor, currency)
          .major;

  /// Whether the wallet alone can pay [priceKr] (whole units of
  /// [currency]): a balance of the trip's currency of at least the fare.
  /// Below it the wallet is not a method for the whole ride (rider-74).
  bool walletCovers(double priceKr) =>
      walletMatchesTrip &&
      Money.fromLegacyMajor(walletBalance, walletCurrency).amountMinor >=
          moneyOf(priceKr).amountMinor;

  /// What the chosen method is charged after the wallet part.
  double remainderKr(double priceKr) => Money(
    walletSplitFor(moneyOf(priceKr).amountMinor).remainderMinor,
    currency,
  ).major;

  /// The wallet / method split of [totalMinor] (minor units of [currency]),
  /// worked out in minor units so the parts always add up to the total.
  /// None until the balance of this trip's currency is known (Q8).
  WalletSplit walletSplitFor(int totalMinor) {
    if (!useWalletFirst || !_flags.enableWallet || !walletMatchesTrip) {
      return WalletSplit.none(totalMinor, currency);
    }
    if (selectedPaymentItem()?.brand == 'wallet') {
      return WalletSplit.none(totalMinor, currency);
    }
    return WalletSplit.of(
      totalMinor: totalMinor,
      balanceMinor: Money.fromLegacyMajor(walletBalance, walletCurrency)
          .amountMinor,
      currency: currency,
    );
  }

  /// Whether the rider has a saved card. Without one, the generic "Card"
  /// method opens Add card first.
  bool get hasSavedCard => _savedCards.hasCards;

  /// The saved cards as payment items (`card:<id>`, "Visa •••• 4242",
  /// "Expires 08/28").
  List<RidePaymentItem> savedCardItems() => [
    for (final card in _savedCards.list())
      RidePaymentItem(
        brand: card.methodBrand,
        name: card.displayName,
        detail: L10n.current.cardExpires(card.expiryLabel),
      ),
  ];

  /// The saved card behind a `card:<id>` brand, or null.
  SavedCard? savedCardFor(String brand) => _savedCards.byMethodBrand(brand);

  /// Loads the saved cards once and keeps the chosen method afterwards.
  Future<void> loadSavedCards() async {
    final current = selectedPaymentItem()?.brand;
    await _savedCards.load();
    _reselect(current);
  }

  List<RidePaymentItem> payments() {
    final platform = defaultTargetPlatform;
    final mobile =
        platform == TargetPlatform.iOS || platform == TargetPlatform.android;
    final cards = savedCardItems();
    return _store.payments().expand<RidePaymentItem>((item) {
      // The generic "Card" row becomes the saved cards once there are any.
      if (item.brand == 'cards') {
        if (cards.isNotEmpty) return cards;
        // Without Add card (staging/production until a payment partner
        // holds cards) the generic row would lead nowhere.
        return CardEntryPolicy.enabled ? [item] : const <RidePaymentItem>[];
      }
      return [item];
    }).where((item) {
      final zoneMethod = zoneMethodOf(item.brand);
      if (zoneMethod != null && !zonePaymentMethods.contains(zoneMethod)) {
        return false;
      }
      if (item.brand == 'cash') return _flags.enableCash;
      // Apple Pay on iPhone, Google Pay on Android (both elsewhere).
      if (item.brand == 'apple') {
        return _flags.enableApplePay &&
            (!mobile || platform == TargetPlatform.iOS);
      }
      if (item.brand == 'google') {
        return _flags.enableGooglePay &&
            (!mobile || platform == TargetPlatform.android);
      }
      if (item.brand == 'wallet') {
        // Q8: the balance of the trip's own currency; no conversion.
        return _flags.enableWallet && walletBalance > 0 && walletMatchesTrip;
      }
      return true;
    }).toList();
  }

  /// Cash is the default until the rider picks something else.
  void _selectDefaultPayment() {
    final list = payments();
    final i = list.indexWhere((item) => item.brand == 'cash');
    selectedPayment = i >= 0 ? i : 0;
  }

  /// Runs [change], which may add or drop payment rows, and keeps the
  /// chosen method on its brand: [selectedPayment] is an index, so a row
  /// that drops out above it would otherwise move the choice to another
  /// method. When the chosen brand itself is gone, the default.
  void _keepPayment(void Function() change) {
    final current = selectedPaymentItem()?.brand;
    change();
    _reselect(current);
  }

  /// After the payment rows changed: the method asked for before it was
  /// offered ([_wanted]) when it now is, else [current] by brand, else
  /// the default.
  void _reselect(String? current) {
    final list = payments();
    final wanted = _wanted;
    if (wanted != null) {
      final i = list.indexWhere(wanted);
      if (i >= 0) {
        selectedPayment = i;
        _wanted = null;
        return;
      }
    }
    if (current != null && list.any((item) => item.brand == current)) {
      selectPaymentByBrand(current);
    } else {
      _selectDefaultPayment();
    }
  }

  /// A method that was asked for (the saved default, or the reservation's
  /// method) before it was offered: the wallet row appears only once the balance has loaded, so
  /// it is chosen when it does (rider-75). A choice the rider makes
  /// meanwhile wins.
  bool Function(RidePaymentItem item)? _wanted;

  int beginQuotes() => ++_quoteGeneration;

  Future<T> _withManagedTimeout<T>(Future<T> source, Duration timeout) {
    final completer = Completer<T>();
    Timer? timer;

    void cancel() {
      timer?.cancel();
      if (!completer.isCompleted) {
        completer.completeError(const _QuoteLoadCancelled());
      }
    }

    _cancelQuoteTimeouts.add(cancel);
    timer = Timer(timeout, () {
      _cancelQuoteTimeouts.remove(cancel);
      if (!completer.isCompleted) {
        completer.completeError(
          TimeoutException('Quote request timed out', timeout),
        );
      }
    });

    source.then<void>(
      (value) {
        timer?.cancel();
        _cancelQuoteTimeouts.remove(cancel);
        if (!completer.isCompleted) completer.complete(value);
      },
      onError: (Object error, StackTrace stack) {
        timer?.cancel();
        _cancelQuoteTimeouts.remove(cancel);
        if (!completer.isCompleted) completer.completeError(error, stack);
      },
    );

    return completer.future;
  }

  void cancelPendingQuotes() {
    if (_disposed) return;
    _quoteGeneration += 1;
    final cancels = _cancelQuoteTimeouts.toList(growable: false);
    _cancelQuoteTimeouts.clear();
    for (final cancel in cancels) {
      cancel();
    }
  }

  bool get hasPendingQuoteRequests => _cancelQuoteTimeouts.isNotEmpty;

  void dispose() {
    if (_disposed) return;
    cancelPendingQuotes();
    _disposed = true;
  }

  Future<void> loadQuotes({
    required int generation,
    required String pickup,
    required String destination,
    int distanceMeters = 3000,
    GeoPoint? pickupPoint,
    GeoPoint? destinationPoint,
    // Audit finding B7 / contract §3: quotes MUST include the stops.
    List<RouteStop> stops = const <RouteStop>[],
    int parallelism = PerformanceBudgets.quoteParallelism,
    Duration timeout = PerformanceBudgets.quoteTimeout,
  }) async {
    usedFallback = false;
    final catalog = rides();
    if (catalog.isEmpty) return;
    final width = parallelism.clamp(1, catalog.length).toInt();

    for (var start = 0; start < catalog.length; start += width) {
      if (generation != _quoteGeneration) return;
      final end = (start + width).clamp(0, catalog.length).toInt();
      final batch = catalog.sublist(start, end);
      await Future.wait<void>(
        batch.map(
          (ride) => _loadQuote(
            rideId: ride.id,
            generation: generation,
            pickup: pickup,
            destination: destination,
            distanceMeters: distanceMeters,
            pickupPoint: pickupPoint,
            destinationPoint: destinationPoint,
            stops: stops,
            timeout: timeout,
          ),
        ),
      );
    }
  }

  Future<void> _loadQuote({
    required String rideId,
    required int generation,
    required String pickup,
    required String destination,
    required int distanceMeters,
    GeoPoint? pickupPoint,
    GeoPoint? destinationPoint,
    List<RouteStop> stops = const <RouteStop>[],
    required Duration timeout,
  }) async {
    if (generation != _quoteGeneration) return;
    try {
      final quote = await _withManagedTimeout(
        _quotes.quote(
          rideType: rideId,
          distanceMeters: distanceMeters,
          pickup: pickup,
          destination: destination,
          pickupPoint: pickupPoint,
          destinationPoint: destinationPoint,
          stops: stops,
        ),
        timeout,
      );
      if (generation != _quoteGeneration) return;
      adoptQuote(rideId, quote);
    } catch (_) {
      if (generation != _quoteGeneration) return;
      offeredPrices.remove(rideId);
      quoteIds.remove(rideId);
      quoteExpiresAt.remove(rideId);
      authoritativeQuotes.remove(rideId);
      unavailableQuoteIds.add(rideId);
    }
  }

  int _pinQuoteGeneration = 0;

  /// Prices [rideId] again from a moved pickup pin. Only the latest call
  /// wins: an older answer that arrives late returns null and is not
  /// adopted, and list loads begun before this call are dropped so they
  /// cannot put the old point's price back (RIDE-11). The adopted quote is
  /// what booking then sends.
  Future<RideQuote?> quoteFromPin({
    required String rideId,
    required int distanceMeters,
    String? pickup,
    String? destination,
    GeoPoint? pickupPoint,
    GeoPoint? destinationPoint,
    List<RouteStop> stops = const <RouteStop>[],
    Duration timeout = PerformanceBudgets.quoteTimeout,
  }) async {
    if (_disposed) return null;
    final generation = ++_pinQuoteGeneration;
    _quoteGeneration += 1;
    final quote = await _withManagedTimeout(
      _quotes.quote(
        rideType: rideId,
        distanceMeters: distanceMeters,
        pickup: pickup,
        destination: destination,
        pickupPoint: pickupPoint,
        destinationPoint: destinationPoint,
        stops: stops,
      ),
      timeout,
    );
    if (_disposed || generation != _pinQuoteGeneration) return null;
    adoptQuote(rideId, quote);
    return quote;
  }

  /// Takes [quote] as the authoritative price for [rideId], exactly as a
  /// loaded quote is. Set location calls this after pricing the ride from
  /// the exact pin, so booking sends that quote.
  void adoptQuote(String rideId, RideQuote quote) {
    if (_disposed) return;
    // The server priced the pickup in another zone's currency: every
    // price held so far was in the old one, and is dropped.
    currency = quote.currency;
    offeredPrices[rideId] = majorOf(quote);
    quoteIds[rideId] = quote.id;
    quoteExpiresAt[rideId] = quote.expiresAt;
    authoritativeQuotes[rideId] = quote;
    unavailableQuoteIds.remove(rideId);
    _expiredQuoteIds.remove(rideId);
  }

  bool quoteIsFresh(String id, {DateTime? now}) {
    final expiresAt = quoteExpiresAt[id];
    if (expiresAt == null) return false;
    return expiresAt.isAfter(now ?? DateTime.now());
  }

  bool quoteIsAvailable(String id, {DateTime? now}) {
    if (unavailableQuoteIds.contains(id)) return false;
    final quote = authoritativeQuotes[id];
    if (quote == null ||
        quote.id.trim().isEmpty ||
        quote.signedPayload == null ||
        quote.signedPayload!.trim().isEmpty) {
      return false;
    }
    if (!quoteIsFresh(id, now: now)) return false;
    if (quote.rideType != id) return false;
    if (quote.currency != currency) return false;
    final offered = offeredPrices[id];
    if (offered == null) return false;
    return moneyOf(offered).amountMinor == quote.totalMinor;
  }

  void _discardExpiredQuote(String id, {DateTime? now}) {
    final expiresAt = quoteExpiresAt[id];
    if (expiresAt == null || expiresAt.isAfter(now ?? DateTime.now())) return;
    offeredPrices.remove(id);
    quoteIds.remove(id);
    quoteExpiresAt.remove(id);
    authoritativeQuotes.remove(id);
    unavailableQuoteIds.add(id);
    _expiredQuoteIds.add(id);
  }

  /// The earliest time a quote held now runs out, or null.
  DateTime? get nextQuoteExpiry {
    DateTime? next;
    for (final at in quoteExpiresAt.values) {
      if (next == null || at.isBefore(next)) next = at;
    }
    return next;
  }

  double priceFor(String id, double catalog, {DateTime? now}) {
    _discardExpiredQuote(id, now: now);
    return offeredPrices[id] ?? catalog;
  }

  double? authoritativePriceFor(String id, {DateTime? now}) {
    if (!quoteIsAvailable(id, now: now)) return null;
    final quote = authoritativeQuotes[id]!;
    return majorOf(quote);
  }

  /// Selects [id]. [catalog] is its list price, held as the price only when
  /// it is in this pickup's currency ([catalogCurrency]).
  void selectRide(
    String id,
    double catalog, {
    String catalogCurrency = Money.defaultCurrency,
  }) {
    selectedRideId = id;
    if (catalogCurrency == currency && !_expiredQuoteIds.contains(id)) {
      offeredPrices.putIfAbsent(id, () => catalog);
    }
  }

  /// Whether [id] has a price to show in this pickup's currency: a quote,
  /// or a list price in the same currency. Not once its quote ran out:
  /// the list price is not that fare (rider-u185).
  bool hasPriceFor(
    String id, {
    required String catalogCurrency,
    DateTime? now,
  }) {
    _discardExpiredQuote(id, now: now);
    return offeredPrices.containsKey(id) ||
        (catalogCurrency == currency && !_expiredQuoteIds.contains(id));
  }

  RidePaymentItem? selectedPaymentItem() {
    final list = payments();
    if (list.isEmpty) {
      selectedPayment = 0;
      return null;
    }
    selectedPayment = selectedPayment.clamp(0, list.length - 1).toInt();
    return list[selectedPayment];
  }

  void selectPayment(int index) {
    final list = payments();
    if (list.isEmpty) {
      selectedPayment = 0;
      return;
    }
    selectedPayment = index.clamp(0, list.length - 1).toInt();
    _wanted = null;
    _persistSelectedBrand();
  }

  void selectPaymentNamed(String? name) {
    final needle = name?.trim();
    if (needle == null || needle.isEmpty) return;
    // Bookings saved before the change said "Pay in car" or "Swish"
    // (removed, owner Q7): both are Cash now.
    final legacy = needle.toLowerCase();
    if (legacy == 'cash' || legacy == 'swish' || legacy == 'pay in car') {
      _wanted = null;
      selectPaymentByBrand('cash');
      return;
    }
    bool named(RidePaymentItem item) =>
        item.name.toLowerCase() == needle.toLowerCase();
    final list = payments();
    final i = list.indexWhere(named);
    if (i >= 0) {
      selectedPayment = i;
      _wanted = null;
    } else {
      // A reservation or return ride paid with Movera Wallet: the wallet
      // row is offered once the balance has loaded (rider-u186).
      _wanted = named;
    }
  }

  void selectPaymentByBrand(String? brand) {
    final needle = brand?.trim();
    if (needle == null || needle.isEmpty) return;
    final list = payments();
    final i = list.indexWhere((item) => item.brand == needle);
    if (i >= 0) selectedPayment = i;
  }

  Future<void> restoreDefaultPayment() async {
    final store = _paymentStore;
    final saved = store == null ? null : await store.read();
    final list = payments();
    if (saved == null || !list.any((item) => item.brand == saved)) {
      _selectDefaultPayment();
      // Not offered yet (the wallet before its balance has loaded).
      if (saved != null) _wanted = (item) => item.brand == saved;
    } else {
      _wanted = null;
      selectPaymentByBrand(saved);
    }
    selectedPaymentItem();
  }

  /// Q7: the zone's payment methods. Keeps the chosen method when it is
  /// still offered, else falls back to the default.
  void setZonePaymentMethods(List<String> methods) {
    _keepPayment(() => zonePaymentMethods = List.unmodifiable(methods));
  }

  /// Keeps the chosen method when the list changes (e.g. the wallet
  /// appears), or takes the one asked for before the wallet was offered.
  void setWalletBalance(double balance) {
    _keepPayment(() => walletBalance = balance);
  }

  void _persistSelectedBrand() {
    final store = _paymentStore;
    if (store == null) return;
    final selected = selectedPaymentItem();
    if (selected == null) return;
    unawaited(store.save(selected.brand));
  }

  void setBookingMode(BookingMode mode) {
    if (lockBookingMode && mode != BookingMode.scheduled) return;
    bookingMode = mode;
    if (mode == BookingMode.now) {
      scheduledFor = null;
    }
  }

  void scheduleFor(DateTime? at) {
    scheduledFor = at;
    if (at == null) {
      if (!lockBookingMode) bookingMode = BookingMode.now;
      return;
    }
    bookingMode = BookingMode.scheduled;
  }

  String? quoteIdFor(String id, {DateTime? now}) {
    _discardExpiredQuote(id, now: now);
    return quoteIds[id];
  }

  RideQuote? quoteForBooking(String id, {DateTime? now}) {
    _discardExpiredQuote(id, now: now);
    return authoritativeQuotes[id];
  }

  DateTime? expiryFor(String id) => quoteExpiresAt[id];

  double changeOffer({
    required String id,
    required double catalog,
    required int delta,
  }) {
    final current = priceFor(id, catalog);
    final next = _fare.nudge(current: current, catalog: catalog, delta: delta);
    offeredPrices[id] = next;
    return next;
  }
}


class _QuoteLoadCancelled implements Exception {
  const _QuoteLoadCancelled();
}
