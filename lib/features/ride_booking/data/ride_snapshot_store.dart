import 'dart:convert';

import 'package:movera_rider/core/contracts/category_ids.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/core/contracts/trip_status.dart';
import 'package:movera_rider/core/web/web_search_interrupted.dart';

import 'package:movera_rider/core/storage/preferences_store.dart';
import 'package:movera_rider/core/logging/app_log.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/matched_driver.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_notes.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/ride_booking/domain/route_stop.dart';

class RideSnapshot {
  static const currentSchemaVersion = 2;

  const RideSnapshot({
    required this.status,
    required this.savedAt,
    DateTime? createdAt,
    required this.pickupAddress,
    required this.destinationAddress,
    required this.pickupLat,
    required this.pickupLng,
    required this.destinationLat,
    required this.destinationLng,
    required this.rideType,
    required this.price,
    required this.paymentMethod,
    this.rideId,
    this.notes = RideNotes.empty,
    this.stops = const <RouteStop>[],
    this.driver,
    this.cancellationReason,
    this.version,
    this.readEpoch,
    this.walletAmountMinor = 0,
    this.serverUpdatedAt,
    this.searchStartedAt,
    this.categoryId,
    this.paymentMethodId,
    this.maxOfferMinor,
    this.currency = Money.defaultCurrency,
    this.arrivalAnnounced = false,
    this.completedAt,
  }) : createdAt = createdAt ?? savedAt;

  final RideStatus status;
  final DateTime savedAt;
  final DateTime createdAt;
  final String pickupAddress;
  final String destinationAddress;
  final double pickupLat;
  final double pickupLng;
  final double destinationLat;
  final double destinationLng;
  final String rideType;
  /// The fare in whole units of [currency] (kronor, euros, dinars).
  final double price;

  /// Q7: the ISO-4217 code of [price] and every amount of this trip, the
  /// currency of its pickup's zone. Snapshots saved before it existed are
  /// kronor.
  final String currency;
  final String paymentMethod;
  final String? rideId;
  final RideNotes notes;

  /// Stops between pickup and destination, in order.
  final List<RouteStop> stops;
  final MatchedDriver? driver;
  final String? cancellationReason;

  /// The realtime transport's ordering number for [status], when known
  /// (Phase 135). Lets a cold restore seed RideSession.authoritativeVersion,
  /// so a stale event from a freshly-reconnected transport (which starts
  /// its own numbering over from zero) is recognized as older instead of
  /// silently accepted and regressing the restored ride.
  final int? version;

  /// RIDE-6: the [RideSnapshotStore.epoch] at the moment this snapshot was
  /// read back from the store (null for a snapshot built in memory). It is
  /// never persisted and survives [copyWith], so a read -> modify -> save
  /// whose read happened before a [RideSnapshotStore.clear] is recognised as
  /// stale by [RideSnapshotStore.save] and can never bring the ride back.
  final int? readEpoch;
  /// "Use wallet balance first": the part of [price] booked to the Movera
  /// Wallet, in öre (0 = none). The rest goes to [paymentMethod].
  final int walletAmountMinor;

  /// ARCH-1: the server's own `updatedAt` for [status] (from the booking
  /// response or a live event). Unlike [savedAt], which is the device clock
  /// at the last local save, this is server ordering data, so restore may
  /// seed RideSession with it.
  final DateTime? serverUpdatedAt;

  /// ARCH-3: when the current driver search started. The "still looking"
  /// mark is measured from here, so a reload does not restart it. Null for
  /// older snapshots, which fall back to [createdAt] (see [searchStart]).
  final DateTime? searchStartedAt;

  /// RIDE-19: the booking's category and payment method ids (not the labels
  /// in [rideType] / [paymentMethod]), so "Try again" can request the same
  /// ride. Null when unknown.
  final String? categoryId;
  final String? paymentMethodId;

  /// ARCH-20 / contract C-4: the highest fare the rider may offer while
  /// searching, in öre. The server's value when it sends one, else set once
  /// from the booked fare, so a raised offer and a reload never move the
  /// ceiling up with it. Null for older snapshots.
  final int? maxOfferMinor;

  /// rider-u49: the rider was already shown "Your driver has arrived" for
  /// this ride's current driver, so a reload does not open it again.
  final bool arrivalAnnounced;
  /// rider-25: when the trip completed (the first time the completion
  /// surface was reached). Unlike [savedAt], which every later save and
  /// backgrounding moves, it stays put; History and the receipt use it.
  /// Null for older snapshots and before completion.
  final DateTime? completedAt;

  DateTime get searchStart => searchStartedAt ?? createdAt;

  /// [price] as contract Money, with [currency]'s exponent.
  Money get fare => Money.fromLegacyMajor(price, currency);

  /// How long a saved ride may go untouched and still be worth restoring.
  ///
  /// The rule exists to stop an abandoned snapshot reviving days later as a
  /// zombie "Finding driver". Twenty minutes is right for a search — none runs
  /// longer — but wrong once a driver is matched: a real trip across Stockholm
  /// can easily outlive it, and the rider would come back to Home mid-journey.
  /// The same goes for a finished trip still owing payment or a rating. So the
  /// window follows the ride's state, not just the clock.
  static const searchWindow = Duration(minutes: 20);
  static const activeRideWindow = Duration(hours: 6);

  Duration get freshnessWindow => status.isMatched || status.isCompletedSurface
      ? activeRideWindow
      : searchWindow;

  bool get isFresh => DateTime.now().difference(savedAt) < freshnessWindow;

  RideSnapshot copyWith({
    RideStatus? status,
    DateTime? savedAt,
    DateTime? createdAt,
    String? pickupAddress,
    String? destinationAddress,
    double? pickupLat,
    double? pickupLng,
    double? destinationLat,
    double? destinationLng,
    String? rideType,
    double? price,
    String? paymentMethod,
    String? rideId,
    RideNotes? notes,
    List<RouteStop>? stops,
    MatchedDriver? driver,
    String? cancellationReason,
    int? version,
    int? readEpoch,
    int? walletAmountMinor,
    DateTime? serverUpdatedAt,
    DateTime? searchStartedAt,
    String? categoryId,
    String? paymentMethodId,
    int? maxOfferMinor,
    String? currency,
    bool? arrivalAnnounced,
    DateTime? completedAt,
  }) {
    return RideSnapshot(
      status: status ?? this.status,
      savedAt: savedAt ?? this.savedAt,
      createdAt: createdAt ?? this.createdAt,
      pickupAddress: pickupAddress ?? this.pickupAddress,
      destinationAddress: destinationAddress ?? this.destinationAddress,
      pickupLat: pickupLat ?? this.pickupLat,
      pickupLng: pickupLng ?? this.pickupLng,
      destinationLat: destinationLat ?? this.destinationLat,
      destinationLng: destinationLng ?? this.destinationLng,
      rideType: rideType ?? this.rideType,
      price: price ?? this.price,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      rideId: rideId ?? this.rideId,
      notes: notes ?? this.notes,
      stops: stops ?? this.stops,
      driver: driver ?? this.driver,
      cancellationReason: cancellationReason ?? this.cancellationReason,
      version: version ?? this.version,
      readEpoch: readEpoch ?? this.readEpoch,
      walletAmountMinor: walletAmountMinor ?? this.walletAmountMinor,
      serverUpdatedAt: serverUpdatedAt ?? this.serverUpdatedAt,
      searchStartedAt: searchStartedAt ?? this.searchStartedAt,
      categoryId: categoryId ?? this.categoryId,
      paymentMethodId: paymentMethodId ?? this.paymentMethodId,
      maxOfferMinor: maxOfferMinor ?? this.maxOfferMinor,
      currency: currency ?? this.currency,
      arrivalAnnounced: arrivalAnnounced ?? this.arrivalAnnounced,
      completedAt: completedAt ?? this.completedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'schemaVersion': currentSchemaVersion,
    'status': status.name,
    'savedAt': savedAt.toUtc().toIso8601String(),
    'createdAt': createdAt.toUtc().toIso8601String(),
    'pickupAddress': pickupAddress,
    'destinationAddress': destinationAddress,
    'pickupLat': pickupLat,
    'pickupLng': pickupLng,
    'destinationLat': destinationLat,
    'destinationLng': destinationLng,
    'rideType': rideType,
    'price': price,
    'paymentMethod': paymentMethod,
    'rideId': rideId,
    'notes': notes.toJson(),
    if (stops.isNotEmpty) 'stops': [for (final stop in stops) stop.toJson()],
    if (driver != null) 'driver': driver!.toJson(),
    if (cancellationReason != null) 'cancellationReason': cancellationReason,
    if (version != null) 'version': version,
    if (walletAmountMinor > 0) 'walletAmountMinor': walletAmountMinor,
    if (serverUpdatedAt != null)
      'serverUpdatedAt': serverUpdatedAt!.toUtc().toIso8601String(),
    if (searchStartedAt != null)
      'searchStartedAt': searchStartedAt!.toUtc().toIso8601String(),
    if (categoryId != null) 'categoryId': categoryId,
    if (paymentMethodId != null) 'paymentMethodId': paymentMethodId,
    if (maxOfferMinor != null) 'maxOfferMinor': maxOfferMinor,
    if (currency != Money.defaultCurrency) 'currency': currency,
    if (arrivalAnnounced) 'arrivalAnnounced': true,
    if (completedAt != null)
      'completedAt': completedAt!.toUtc().toIso8601String(),
  };

  static RideSnapshot? fromJson(Map<String, dynamic> json) {
    final schemaVersion = (json['schemaVersion'] as num?)?.toInt() ?? 1;
    if (schemaVersion < 1 || schemaVersion > currentSchemaVersion) return null;

    final statusName = json['status'];
    if (statusName is! String) return null;
    // Device-local storage keeps the UI enum name, not the wire status.
    final parsedStatus = RideStatusWire.legacyName(statusName);
    if (parsedStatus == null) return null;

    final savedRaw = json['savedAt'];
    if (savedRaw is! String) return null;
    final savedParsed = DateTime.tryParse(savedRaw);
    if (savedParsed == null) return null;
    final savedAt = savedParsed.toUtc();

    final createdRaw = json['createdAt'];
    final createdParsed = createdRaw is String ? DateTime.tryParse(createdRaw) : null;
    // v1 did not persist creation time. Preserve its original persisted time
    // rather than manufacturing a new timestamp during migration.
    final createdAt = (createdParsed ?? savedParsed).toUtc();

    final pickupAddress = json['pickupAddress'];
    final destinationAddress = json['destinationAddress'];
    final pickupLat = json['pickupLat'];
    final pickupLng = json['pickupLng'];
    final destinationLat = json['destinationLat'];
    final destinationLng = json['destinationLng'];
    final rideType = json['rideType'];
    final price = json['price'];
    final paymentMethod = json['paymentMethod'];
    if (pickupAddress is! String ||
        destinationAddress is! String ||
        pickupLat is! num ||
        pickupLng is! num ||
        destinationLat is! num ||
        destinationLng is! num ||
        rideType is! String ||
        price is! num ||
        paymentMethod is! String) {
      return null;
    }

    final rideIdRaw = json['rideId'];
    final rideId = rideIdRaw is String ? rideIdRaw.trim() : null;
    if (rideIdRaw != null && (rideId == null || rideId.isEmpty)) return null;

    return RideSnapshot(
      status: parsedStatus,
      savedAt: savedAt,
      createdAt: createdAt,
      pickupAddress: pickupAddress,
      destinationAddress: destinationAddress,
      pickupLat: pickupLat.toDouble(),
      pickupLng: pickupLng.toDouble(),
      destinationLat: destinationLat.toDouble(),
      destinationLng: destinationLng.toDouble(),
      rideType: rideType,
      price: price.toDouble(),
      paymentMethod: paymentMethod,
      rideId: rideId,
      stops: RouteStop.listFromJson(json['stops']),
      notes: RideNotes.fromJson(
        json['notes'] is Map
            ? Map<String, dynamic>.from(json['notes'] as Map)
            : null,
      ),
      driver: json['driver'] is Map
          ? MatchedDriver.fromJson(
              Map<String, dynamic>.from(json['driver'] as Map),
            )
          : null,
      cancellationReason: json['cancellationReason'] as String?,
      version: (json['version'] as num?)?.toInt(),
      walletAmountMinor: (json['walletAmountMinor'] as num?)?.round() ?? 0,
      serverUpdatedAt: _utcOrNull(json['serverUpdatedAt']),
      searchStartedAt: _utcOrNull(json['searchStartedAt']),
      arrivalAnnounced: json['arrivalAnnounced'] == true,
      categoryId: CategoryIds.tryCanonical(json['categoryId']) ??
          _nonEmpty(json['categoryId']),
      paymentMethodId: _nonEmpty(json['paymentMethodId']),
      maxOfferMinor: _positiveMinor(json['maxOfferMinor']),
      currency:
          Money.normalizeCurrency(json['currency']) ?? Money.defaultCurrency,
      completedAt: _utcOrNull(json['completedAt']),
    );
  }
}

DateTime? _utcOrNull(Object? raw) =>
    raw is String ? DateTime.tryParse(raw)?.toUtc() : null;

int? _positiveMinor(Object? raw) =>
    raw is num && raw.isFinite && raw > 0 ? raw.round() : null;

String? _nonEmpty(Object? raw) =>
    raw is String && raw.trim().isNotEmpty ? raw.trim() : null;

class RideSnapshotStore {
  /// SharedPreferences key. On Flutter web this is `flutter.movera_active_ride`.
  static const key = 'movera_active_ride';
  static const webStorageKey = 'flutter.movera_active_ride';
  static const _writeIdField = '_moveraSnapshotWriteId';

  /// Bumped synchronously on every [clear] so a save can detect that it became
  /// stale while awaiting SharedPreferences/platform persistence.
  static int _epoch = 0;
  static int get epoch => _epoch;
  static set epoch(int value) {
    _epoch = value;
    // Tests reset epoch between cases; reset the lifecycle intent too so no
    // previous test can poison a later one.
    if (value == 0) {
      _intentSerial = 0;
      _lifecycleRefreshBlocked = false;
      _activeRideId = null;
    }
  }

  /// Changes synchronously whenever business logic explicitly saves or clears
  /// ride state. Lifecycle timestamp refreshes capture this value so they
  /// cannot outlive a newer ride decision.
  static int _intentSerial = 0;
  static bool _lifecycleRefreshBlocked = false;
  static String? _activeRideId;

  /// Monotonic process-local identity for each persisted write.
  ///
  /// It is embedded in the stored JSON as an ignored metadata field. That lets
  /// a stale writer clean up only its own value instead of blindly deleting the
  /// shared key and potentially removing a newer ride.
  static int _writeSerial = 0;

  static Future<void> save(RideSnapshot snapshot) async {
    // RIDE-6: a snapshot read before a clear belongs to a ride that has since
    // been cancelled or closed. Writing it back would resurrect that ride on
    // the next cold start, so the write generation it was read at must still
    // be current.
    final readEpoch = snapshot.readEpoch;
    if (readEpoch != null && readEpoch != epoch) {
      AppLog.info(
        'ride_snapshot.stale_save_dropped',
        extra: {'rideId': snapshot.rideId, 'status': snapshot.status.name},
      );
      return;
    }
    _intentSerial += 1;

    if (snapshot.status.isTerminal) {
      _lifecycleRefreshBlocked = true;
      _activeRideId = snapshot.rideId;
      return;
    }

    _lifecycleRefreshBlocked = false;
    _activeRideId = snapshot.rideId;

    // A live ride is worth remembering across a reload so the same trip
    // reopens instead of dumping the rider on Home.
    markSearchLive();

    final token = readEpoch ?? epoch;
    final writeId = ++_writeSerial;
    final payload = <String, dynamic>{
      ...snapshot.toJson(),
      _writeIdField: writeId,
    };
    final encoded = jsonEncode(payload);

    try {
      final prefs = await PreferencesStore.load();
      if (token != epoch) return;

      await prefs.setString(key, encoded);

      if (token != epoch) {
        // Never perform an unconditional stale rollback. Read and compare
        // without an await between the comparison and remove invocation, so
        // a newer save cannot be mistaken for this write. The unique write
        // id also makes two otherwise-identical snapshots distinguishable.
        if (prefs.getString(key) == encoded) {
          await prefs.remove(key);
        }
      }
    } catch (error) {
      // uat-r1: the reload snapshot is best effort. A refused write (iOS
      // Safari: quota, Private Browsing on older iOS, "Block All Cookies")
      // must not fail the booking it follows nor throw out of Finding's
      // unawaited saves; the ride goes on server-side without it.
      AppLog.warning(
        'ride_snapshot.write_refused',
        extra: {
          'rideId': snapshot.rideId,
          'status': snapshot.status.name,
          'error': error.toString(),
        },
      );
    }
  }

  /// Refreshes only the snapshot that is still current at the instant this
  /// lifecycle operation starts.
  ///
  /// Unlike `read() -> save(snapshot)`, this never turns an old read into a
  /// brand-new save after cancellation. Any explicit save/clear invalidates the
  /// captured intent. A clear also blocks lifecycle refresh synchronously while
  /// its SharedPreferences removal is still in flight.
  static Future<void> touchCurrent() async {
    if (_lifecycleRefreshBlocked) return;

    final token = epoch;
    final intentToken = _intentSerial;
    final expectedRideId = _activeRideId;

    final prefs = await PreferencesStore.load();
    if (token != epoch ||
        intentToken != _intentSerial ||
        _lifecycleRefreshBlocked) {
      return;
    }

    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return;

    Map<String, dynamic> decoded;
    try {
      final value = jsonDecode(raw);
      if (value is! Map<String, dynamic>) return;
      decoded = Map<String, dynamic>.from(value);
    } catch (_) {
      return;
    }

    final snapshot = RideSnapshot.fromJson(decoded);
    if (snapshot == null ||
        snapshot.status.isTerminal ||
        !snapshot.isFresh) {
      return;
    }

    if (expectedRideId != null && snapshot.rideId != expectedRideId) {
      return;
    }

    final writeId = ++_writeSerial;
    decoded['savedAt'] = DateTime.now().toUtc().toIso8601String();
    decoded[_writeIdField] = writeId;
    final encoded = jsonEncode(decoded);

    if (token != epoch ||
        intentToken != _intentSerial ||
        _lifecycleRefreshBlocked) {
      return;
    }

    markSearchLive();
    await prefs.setString(key, encoded);

    if (token != epoch ||
        intentToken != _intentSerial ||
        _lifecycleRefreshBlocked) {
      if (prefs.getString(key) == encoded) {
        await prefs.remove(key);
      }
    }
  }

  static Future<RideSnapshot?> read() async {
    final snapshot = await _readStored();
    if (snapshot == null || !snapshot.isFresh || snapshot.status.isTerminal) {
      return null;
    }
    return snapshot;
  }

  /// Reads the last persisted ride specifically for terminal History archival.
  ///
  /// Unlike [read], this intentionally ignores [RideSnapshot.isFresh]
  /// entirely. A legitimate long trip must still be archived before its active
  /// snapshot is cleared, however stale the snapshot has gone.
  static Future<RideSnapshot?> readForArchive() => _readStored();

  static Future<RideSnapshot?> _readStored() async {
    // Captured before the await: a clear that lands while prefs load must
    // still make this read stale.
    final token = epoch;
    final prefs = await PreferencesStore.load();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final snapshot = RideSnapshot.fromJson(decoded);
      if (snapshot == null) return null;
      return snapshot.copyWith(readEpoch: token);
    } catch (error, stackTrace) {
      AppLog.error(
        'ride_snapshot.read_failed',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  static Future<void> clear() async {
    _epoch += 1;
    _intentSerial += 1;
    _lifecycleRefreshBlocked = true;
    _activeRideId = null;
    final prefs = await PreferencesStore.load();
    await prefs.remove(key);
  }
}
