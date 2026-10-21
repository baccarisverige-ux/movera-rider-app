import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:movera_rider/core/api/safety_mock_api.dart';
import 'package:movera_rider/core/utils/request_id.dart';
import 'package:movera_rider/core/api/mock_catalog_fares.dart';
import 'package:movera_rider/core/config/rider_app_config.dart';
import 'package:movera_rider/core/config/rider_zones.dart';
import 'package:movera_rider/core/contracts/cancel_fee.dart';
import 'package:movera_rider/core/contracts/cancel_reasons.dart';
import 'package:movera_rider/core/contracts/category_ids.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/core/contracts/ride_status.dart';
import 'package:movera_rider/core/contracts/trip_settlement.dart';
import 'package:movera_rider/core/contracts/trip_status.dart';
import 'package:movera_rider/core/contracts/trip_transitions.dart';
import 'package:movera_rider/core/contracts/wire_time.dart';
import 'package:movera_rider/core/logging/app_log.dart';
import 'package:movera_rider/core/maps/geo_distance.dart';
import 'package:movera_rider/core/storage/preferences_store.dart';

/// In-process `/api/v1` used on GitHub Pages and tests.
/// Swap [ApiClient] transport to a live HTTP client later — same paths.
///
/// Contract v0.3.0 (`contracts/contract.json`): rides are stored and sent
/// with a snake_case `status` (`TripStatus`), `paymentStatus` and
/// `ratingStatus` fields, `tripId` (with the legacy `rideId`/`id` aliases),
/// and every lifecycle change goes through [TripStateMachine]: a command the
/// table does not allow answers `409 invalid_transition` with the current
/// `projection` and changes nothing.
class InProcessMockClient extends http.BaseClient {
  InProcessMockClient({
    this.latency = Duration.zero,
    this.searchExpiresAfter = const Duration(minutes: 3),
    this.persistSafety = false,
    this.persistRides = false,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// The time the cancel-fee windows are measured with (tests move it).
  final DateTime Function() _clock;

  /// X7: the rider config the stand-in server charges cancel fees from
  /// (`cancelFees.live` / `.reservation` per category). Tests may replace it.
  RiderAppConfig riderConfig = SeedRiderConfigRepository.seed;

  /// When a driver accepted each trip (the start of the live free-cancel
  /// window). Server-side only; not part of the projection.
  final Map<String, DateTime> _acceptedAt = {};

  /// R-O1: the distance each trip has been driven with the rider on board,
  /// summed from the driver's GPS fixes (`POST …/status` with `lat`/`lng`)
  /// since the first fix after boarding. Server-side only; not part of the
  /// projection (contract v0.3.0 has no driven-distance field).
  final Map<String, ({double lat, double lng, double meters})> _driven = {};

  /// Trips the rider ended early. R-O6 (owner decision): they are rated on
  /// the normal trip-end screen. The projection does not say which command
  /// ended a `cancelled_by_rider` trip, so the server remembers it for
  /// `contract.json#ratingAllowed` (v0.3.1).
  final Set<String> _endedEarly = {};

  /// The distance [tripId] has been driven on board, in metres (R-O1).
  int drivenMetersOf(String tripId) => (_driven[tripId]?.meters ?? 0).round();

  final Duration latency;

  /// FLOW-9: keep the Safety mock's state across launches (the app's own
  /// demo transport). Off for tests that build a mock of their own.
  final bool persistSafety;

  /// rider-u10: keep the trips across launches (the app's own demo
  /// transport). A reload restores the ride screen from the snapshot; with
  /// the trips in memory only, every command on the restored ride (rating
  /// and tip, offer raise, route change) then answered 404. Off for tests
  /// that build a mock of their own.
  final bool persistRides;

  /// Where [persistRides] keeps them; a `movera_` key, so a sign-out wipe
  /// removes it.
  static const ridesStorageKey = 'movera_mock_rides_v1';

  /// The newest trips kept; older ones are not saved.
  static const persistedRidesLimit = 20;
  bool _ridesRestored = false;
  String? _savedRides;

  /// ARCH-3: like a real backend, the mock ends a search nobody accepted.
  /// A ride still searching this long after it was created reads back as
  /// `noDriverFound`, so the demo still ends when no driver is assigned.
  final Duration searchExpiresAfter;
  /// RC-12: replays by `METHOD path key`, each with the body it answered
  /// and an encoded copy of that answer (never the live trip map, which
  /// keeps changing). Bounded: entries older than [idempotencyTtl] go, and
  /// past [idempotencyLimit] the oldest go first.
  final Map<String, IdempotentReplay> idempotency = {};
  static const idempotencyTtl = Duration(hours: 24);
  static const idempotencyLimit = 500;
  final Map<String, Map<String, dynamic>> rides = {};
  final Map<String, Map<String, dynamic>> quotes = {};

  /// ARCH-14 / contract C-7: priced route changes, by route-quote id.
  final Map<String, Map<String, dynamic>> routeQuotes = {};
  final Map<String, Map<String, dynamic>> otpSessions = {};

  /// Phones that have verified a code before: their riders are returning.
  final Set<String> knownPhones = {};

  /// Apple/Google accounts that already have a verified phone.
  final Set<String> linkedProviders = {};

  /// Link tokens issued for provider sign-ins still waiting for a phone.
  final Map<String, String> pendingLinks = {};
  final Map<String, Map<String, dynamic>> pushDevices = {};
  final Map<String, Map<String, dynamic>> paymentIntents = {};

  /// Last profile sent with `PATCH /api/v1/rider/profile` (FLOW-7).
  Map<String, dynamic>? riderProfile;

  /// The rider's default payment method on the server (ARCH-7).
  String defaultPaymentMethodId = 'cash';

  /// The demo rider's promotion; tests may replace or clear it.
  Map<String, dynamic>? activePromotion = {
    'id': 'promo_demo_30',
    'title': '30% off your next 5 rides',
    'percentOff': 30,
    'ridesLeft': 4,
    'ridesTotal': 5,
    'endsAt': '2026-11-30T23:59:00Z',
    'maxDiscountMinor': 5000,
    'rideTypes': ['comfort', 'priority', 'premium'],
    'rules': [
      'Applies to Comfort, Priority and Premium.',
      'Up to kr 50 off each ride.',
    ],
  };
  /// Rider-side scheduled-ride rules as Admin › Dispatch › Reservations
  /// publishes them (PROPOSED). Values are the admin defaults: free cancel
  /// until 60 min before pickup, then a kr 50 fee; the driver shows as soon
  /// as one accepts. Tests may edit this map.
  final Map<String, dynamic> scheduledRideRules = {
    'freeCancelMinutesBeforePickup': 60,
    'lateCancelFeeMinor': 5000,
    'currency': currency,
    'showDriverOnAccept': true,
  };
  final Map<String, dynamic> accountSecurity = {
    'phone': '',
    'email': '',
    'phoneVerifiedAt': null,
    'emailVerifiedAt': null,
    'passkeyEnabled': false,
    'twoStepEnabled': false,
    'authenticatorEnabled': false,
    'passwordUpdatedAt': null,
    'recoveryPhone': null,
    'googleConnected': false,
    'appleConnected': false,
    'reauthenticatedAt': null,
    'capabilities': {
      'passkeys': false,
      'password': false,
      'authenticator': false,
      'twoStep': false,
      'recoveryPhone': false,
      'connectedAccounts': false,
      'reauthentication': false,
      'signOutOtherDevices': false,
    },
    'sessions': [
      {
        'id': 'session_current',
        'device': 'This device',
        'place': '',
        'source': 'Movera',
        'current': true,
      },
    ],
  };
  /// The process-wide Safety mock, looked up on each use so a sign-out
  /// reset (UserDataWipe) reaches every client.
  SafetyMockApi get safety => safetyMockForProcess();
  bool failNext = false;
  Duration? timeoutNext;

  static const currency = 'SEK';

  /// Ride categories as the admin panel publishes them (`GET /ride-types`).
  /// `van` is not in the app's built-in list: it proves the catalog really
  /// comes from here. Tests may edit this list.
  final List<Map<String, dynamic>> rideTypes = [
    _rideType('economy', 'Movera', 4, 8, 259, 'Affordable and convenient rides',
        order: 1, badge: 'RECOMMENDED'),
    _rideType('comfort', 'Comfort', 4, 11, 339, 'Newer cars with extra legroom',
        order: 2),
    _rideType('premium', 'Premium', 4, 11, 369,
        'Premium cars with top-rated drivers',
        order: 3),
    _rideType('priority', 'Priority', 4, 6, 289, 'More options, less waiting',
        order: 4, badge: 'FASTER'),
    _rideType('xl', 'Movera XL', 6, 12, 399, 'Cars for larger groups (6 people)',
        order: 5),
    _rideType('electric', 'Electric', 4, 9, 259, 'Quiet and fossil-free cars',
        order: 6, glyph: 'bolt'),
    _rideType('pet', 'Movera Pet', 4, 10, 279, 'Pet-friendly rides',
        order: 7, glyph: 'pets'),
    _rideType('van', 'Van', 8, 14, 449, 'Groups and luggage',
        order: 8, glyph: 'van'),
    _rideType('wheelchair', 'Wheelchair', 4, 15, 289,
        'Ramp or lift, driver helps on board',
        order: 9, glyph: 'wheelchair'),
    _rideType('business', 'Business', 4, 10, 399,
        'Quiet ride, receipt for your company',
        order: 10, glyph: 'briefcase'),
    _rideType('airport', 'Airport', 4, 12, 429,
        'Fixed price, flight tracked, extra luggage',
        order: 11, glyph: 'plane'),
    _rideType('kids', 'Kids seat', 4, 12, 279, 'Child seat already fitted',
        order: 12, glyph: 'child'),
    _rideType('women', 'Women driver', 4, 13, 279,
        'A woman behind the wheel',
        order: 13, glyph: 'person'),
    _rideType('delivery', 'Delivery', 2, 9, 199, 'Send a parcel across town',
        order: 14, glyph: 'parcel'),
  ];

  static Map<String, dynamic> _rideType(
    String id,
    String name,
    int seats,
    int etaMin,
    int price,
    String description, {
    required int order,
    String? badge,
    String? glyph,
    String? imageKey,
    bool enabled = true,
  }) {
    return {
      'id': id,
      'name': name,
      'seats': seats,
      'etaMin': etaMin,
      // The list price as Money (contract v0.3.0).
      'price': _money(price * Money.minorPerMajor(currency)),
      'description': description,
      'badge': badge,
      'glyph': glyph,
      'imageKey': imageKey ?? id,
      'order': order,
      'enabled': enabled,
    };
  }

  /// Catalog price in kr for [rideType]: the ride-types table first, then
  /// the dev fallback table.
  int _catalogPriceKr(String rawType) {
    final rideType = CategoryIds.canonical(rawType);
    for (final type in rideTypes) {
      if (type['id'] == rideType) {
        final price = type['price'];
        if (price is Map && price['amountMinor'] is int) {
          return (price['amountMinor'] as int) ~/ 100;
        }
        if (price is num) return price.round();
      }
    }
    return mockCatalogPricesKr[rideType] ?? 259;
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (timeoutNext != null) {
      final wait = timeoutNext!;
      timeoutNext = null;
      await Future<void>.delayed(wait);
      throw TimeoutException('mock timeout');
    }
    if (latency > Duration.zero) {
      await Future<void>.delayed(latency);
    }
    if (persistRides) {
      await _restoreRidesOnce();
      final response = await _handle(request);
      await _persistRides();
      return response;
    }
    return _handle(request);
  }

  /// Loads the trips an earlier launch saved, once per mock instance.
  Future<void> _restoreRidesOnce() async {
    if (_ridesRestored) return;
    _ridesRestored = true;
    try {
      final raw = (await PreferencesStore.load()).getString(ridesStorageKey);
      if (raw == null) return;
      final saved = jsonDecode(raw);
      if (saved is! Map) return;
      final trips = saved['rides'];
      if (trips is Map) {
        for (final entry in trips.entries) {
          if (entry.value is Map) {
            rides.putIfAbsent(
              '${entry.key}',
              () => Map<String, dynamic>.from(entry.value as Map),
            );
          }
        }
      }
      final accepted = saved['acceptedAt'];
      if (accepted is Map) {
        for (final entry in accepted.entries) {
          final at = WireTime.tryParse(entry.value);
          if (at != null) _acceptedAt.putIfAbsent('${entry.key}', () => at);
        }
      }
      final endedEarly = saved['endedEarly'];
      if (endedEarly is List) _endedEarly.addAll(endedEarly.whereType<String>());
      _savedRides = raw;
    } catch (error) {
      AppLog.warning('mock.rides_restore_failed', extra: {'error': '$error'});
    }
  }

  /// Saves the newest trips when a request changed them.
  Future<void> _persistRides() async {
    try {
      final keep = rides.keys.toList();
      final recent = keep.length > persistedRidesLimit
          ? keep.sublist(keep.length - persistedRidesLimit)
          : keep;
      final encoded = jsonEncode({
        'rides': {for (final id in recent) id: rides[id]},
        'acceptedAt': {
          for (final id in recent)
            if (_acceptedAt[id] case final at?) id: WireTime.format(at),
        },
        'endedEarly': [for (final id in recent) if (_endedEarly.contains(id)) id],
      });
      if (encoded == _savedRides) return;
      _savedRides = encoded;
      await (await PreferencesStore.load()).setString(ridesStorageKey, encoded);
    } catch (error) {
      AppLog.warning('mock.rides_persist_failed', extra: {'error': '$error'});
    }
  }

  Future<http.StreamedResponse> _handle(http.BaseRequest request) async {
    final requestId = request.headers['X-Request-Id'] ?? newRequestId();
    final key = request.headers['Idempotency-Key'];
    final path = request.url.path;
    final method = request.method.toUpperCase();
    var body = <String, dynamic>{};
    if (request is http.Request && request.body.isNotEmpty) {
      final decoded = jsonDecode(request.body);
      if (decoded is Map<String, dynamic>) body = decoded;
    }

    if (failNext) {
      failNext = false;
      return _json(
        500,
        _error('internal', requestId, message: 'Mock 500'),
        requestId,
      );
    }

    final replayKey = key == null || key.isEmpty ? null : '$method $path $key';
    final bodyKey = jsonEncode(body);
    if (replayKey != null) {
      _evictIdempotency();
      final replay = idempotency[replayKey];
      if (replay != null) {
        // Contract §1: the same key with a different body is refused.
        if (replay.body != bodyKey) {
          return _json(
            409,
            _error(
              'conflict',
              requestId,
              reason: 'idempotency_key_reused',
              message: 'This Idempotency-Key was used with another body.',
            ),
            requestId,
          );
        }
        return _json(
          200,
          jsonDecode(replay.response) as Map<String, dynamic>,
          requestId,
        );
      }
    }

    late Map<String, dynamic> payload;
    var status = 200;
    final parts = path.split('/');

    if (path == '/api/v1/locations/reverse-geocode' && method == 'POST') {
      final latitude = body['latitude'];
      final longitude = body['longitude'];
      if (latitude is! num || longitude is! num) {
        status = 400;
        payload = _error('invalid_request', requestId, reason: 'invalid_coordinates');
      } else {
        payload = {
          'code': 'OK',
          'data': {
            'latitude': latitude.toDouble(),
            'longitude': longitude.toDouble(),
            // The in-process transport has no external geocoder. Preserve the
            // real device coordinates and expose a neutral label instead of
            // failing the entire location pipeline.
            'address': 'Current location',
          },
          'requestId': requestId,
        };
      }
    } else if (path == '/api/v1/locations/geocode' && method == 'POST') {
      final query = body['query'];
      if (query is! String || query.trim().isEmpty) {
        status = 400;
        payload = _error('invalid_request', requestId, reason: 'invalid_query');
      } else {
        final normalized = query.trim();
        // A known demo place geocodes to where it really is (Arlanda is not
        // next to Stockholm Central); anything else gets a stable made-up
        // point so demo bookings still work.
        final known = _demoSuggestions(
          normalized,
          typedFallback: false,
        ).firstOrNull;
        if (known != null) {
          payload = {
            'code': 'OK',
            'data': {
              'address': normalized,
              'latitude': known['latitude'],
              'longitude': known['longitude'],
            },
            'requestId': requestId,
          };
          return _json(status, payload, requestId);
        }
        final hash = normalized.toLowerCase().codeUnits.fold<int>(
          0,
          (value, unit) => ((value * 31) + unit) & 0x7fffffff,
        );
        // Deterministic demo coordinates keep the frontend booking contract
        // operational on GitHub Pages until the real geocoder is connected.
        final latitude = 59.3293 + (((hash % 1201) - 600) / 100000.0);
        final longitude = 18.0686 + ((((hash ~/ 1201) % 1601) - 800) / 100000.0);
        payload = {
          'code': 'OK',
          'data': {
            'address': normalized,
            'latitude': latitude,
            'longitude': longitude,
          },
          'requestId': requestId,
        };
      }
    } else if (path == '/api/v1/locations/autocomplete' && method == 'POST') {
      final query = body['query'];
      payload = {
        'code': 'OK',
        'suggestions': query is String ? _demoSuggestions(query) : const [],
        'requestId': requestId,
      };
    } else if (path == '/api/v1/auth/otp/request' && method == 'POST') {
      final phone = body['phone'];
      final linkToken = body['linkToken'];
      if (phone is! String || phone.trim().isEmpty) {
        status = 400;
        payload = _error('invalid_request', requestId, reason: 'invalid_phone');
      } else if (linkToken != null &&
          (linkToken is! String || !pendingLinks.containsKey(linkToken))) {
        status = 400;
        payload = _error('invalid_request', requestId, reason: 'invalid_link');
      } else {
        final sessionId = 'otp_${newRequestId()}';
        final expiresAt = DateTime.now()
            .toUtc()
            .add(const Duration(minutes: 5));
        otpSessions[sessionId] = {
          'phone': phone.trim(),
          if (linkToken is String) 'linkToken': linkToken,
          'code': '1234',
          'expiresAt': expiresAt.toIso8601String(),
        };
        payload = {
          'code': 'OK',
          'requestId': requestId,
          'sessionId': sessionId,
          'expiresAt': expiresAt.toIso8601String(),
          'retryAfterSeconds': 30,
        };
      }
    } else if (path == '/api/v1/auth/otp/verify' && method == 'POST') {
      final phone = body['phone'];
      final sessionId = body['sessionId'];
      final code = body['code'];
      final session = sessionId is String ? otpSessions[sessionId] : null;
      if (session == null ||
          phone is! String ||
          code is! String ||
          session['phone'] != phone.trim()) {
        status = 400;
        payload = _error('invalid_request', requestId, reason: 'invalid_otp_session');
      } else {
        final expiresAt = DateTime.tryParse('${session['expiresAt'] ?? ''}');
        if (expiresAt == null || !expiresAt.isAfter(DateTime.now().toUtc())) {
          status = 410;
          payload = _error('invalid_request', requestId, reason: 'otp_expired');
        } else if (session['code'] != code.trim()) {
          status = 401;
          payload = _error('unauthenticated', requestId, reason: 'invalid_otp');
        } else {
          otpSessions.remove(sessionId);
          final normalizedPhone = phone.trim();
          final isNewRider = knownPhones.add(normalizedPhone);
          final linkToken = session['linkToken'];
          final provider = linkToken is String ? pendingLinks.remove(linkToken) : null;
          if (provider != null) {
            // The provider account now has a verified phone.
            linkedProviders.add(provider);
          }
          final kind = provider ?? 'phone';
          payload = {
            'code': 'OK',
            'accessToken': 'mock-access-$kind-$sessionId',
            'refreshToken': 'mock-refresh-$kind-$sessionId',
            'isNewRider': isNewRider,
            'requestId': requestId,
          };
        }
      }
    } else if (path == '/api/v1/auth/provider' && method == 'POST') {
      final provider = body['provider'];
      if (provider is! String || provider.trim().isEmpty) {
        status = 400;
        payload = _error('invalid_request', requestId, reason: 'invalid_provider');
      } else if (!linkedProviders.contains(provider.trim())) {
        // First sign-in with this account: no session until a phone is
        // verified, only a short-lived link token.
        final linkToken = 'link_${provider.trim()}_${newRequestId()}';
        pendingLinks[linkToken] = provider.trim();
        payload = {
          'code': 'PHONE_REQUIRED',
          'linkToken': linkToken,
          'requestId': requestId,
        };
      } else {
        payload = {
          'code': 'OK',
          'accessToken': 'mock-access-${provider.trim()}',
          'refreshToken': 'mock-refresh-${provider.trim()}',
          'requestId': requestId,
        };
      }
    } else if (path == '/api/v1/auth/refresh' && method == 'POST') {
      final refreshToken = body['refreshToken'];
      if (refreshToken is! String || !refreshToken.startsWith('mock-refresh-')) {
        status = 401;
        payload = _error('unauthenticated', requestId, reason: 'invalid_refresh');
      } else {
        payload = {
          'code': 'OK',
          'accessToken': 'mock-access-refreshed-${newRequestId()}',
          'refreshToken': 'mock-refresh-rotated-${newRequestId()}',
          'requestId': requestId,
        };
      }
    } else if (path == '/api/v1/auth/sign-out' && method == 'POST') {
      payload = {'code': 'OK', 'requestId': requestId};
    } else if (path == '/api/v1/account/deletion' && method == 'POST') {
      // Accepted, not done: the backend erases the account on its own
      // schedule (retention rules, open payments), hence 202.
      status = 202;
      payload = {'code': 'OK', 'status': 'scheduled', 'requestId': requestId};
    } else if (path == '/api/v1/push/devices' && method == 'POST') {
      final token = body['token'];
      final provider = body['provider'];
      final platform = body['platform'];
      if (token is! String ||
          token.trim().isEmpty ||
          provider != 'fcm' ||
          platform is! String ||
          platform.trim().isEmpty) {
        status = 400;
        payload = _error('invalid_request', requestId, reason: 'invalid_push_device');
      } else {
        final normalized = token.trim();
        pushDevices[normalized] = {
          'token': normalized,
          'provider': 'fcm',
          'platform': platform.trim(),
        };
        payload = {
          'code': 'OK',
          'status': 'registered',
          'requestId': requestId,
        };
      }
    } else if (path == '/api/v1/push/devices/unregister' &&
        method == 'POST') {
      final token = body['token'];
      if (token is! String || token.trim().isEmpty) {
        status = 400;
        payload = _error('invalid_request', requestId, reason: 'invalid_push_device');
      } else {
        pushDevices.remove(token.trim());
        payload = {
          'code': 'OK',
          'status': 'unregistered',
          'requestId': requestId,
        };
      }
    } else if (path == '/api/v1/account/security' && method == 'GET') {
      payload = {
        'code': 'OK',
        'security': accountSecurity,
        'requestId': requestId,
      };
    } else if (path == '/api/v1/account/security/sessions/sign-out-others' &&
        method == 'POST') {
      final reauthenticatedAt = DateTime.tryParse(
        '${accountSecurity['reauthenticatedAt'] ?? ''}',
      );
      final now = DateTime.now().toUtc();
      final age = reauthenticatedAt == null
          ? null
          : now.difference(reauthenticatedAt.toUtc());
      final fresh = age != null &&
          !age.isNegative &&
          age <= const Duration(minutes: 5);
      if (!fresh) {
        status = 403;
        payload = _error(
          'forbidden',
          requestId,
          reason: 'reauth_required',
          message: 'Fresh reauthentication is required.',
        );
      } else {
        final sessions = accountSecurity['sessions'];
        if (sessions is List) {
          accountSecurity['sessions'] = sessions
              .whereType<Map>()
              .where((item) => item['current'] == true)
              .map((item) => Map<String, dynamic>.from(item))
              .toList();
        }
        accountSecurity['reauthenticatedAt'] = null;
        payload = {
          'code': 'OK',
          'security': accountSecurity,
          'requestId': requestId,
        };
      }
    } else if (path == '/api/v1/routes' && method == 'POST') {
      final from = body['from'];
      final to = body['to'];
      final fromMap = from is Map ? Map<String, dynamic>.from(from) : const <String, dynamic>{};
      final toMap = to is Map ? Map<String, dynamic>.from(to) : const <String, dynamic>{};
      payload = {
        'code': 'OK',
        'points': [
          {'lat': fromMap['lat'], 'lng': fromMap['lng']},
          {'lat': toMap['lat'], 'lng': toMap['lng']},
        ],
        'provider': 'movera-controlled',
        'requestId': requestId,
      };
    } else if (path == '/api/v1/quotes' && method == 'POST') {
      final quote = _quote(body);
      quotes[quote['id'] as String] = quote;
      payload = {'code': 'OK', 'quote': quote, 'requestId': requestId};
    } else if (path == '/api/v1/rides' && method == 'POST') {
      final validation = _validateQuoteBinding(body);
      if (validation != null) {
        status = 409;
        payload = _error(
          validation == 'wallet_amount_invalid' ? 'invalid_request' : 'conflict',
          requestId,
          reason: validation,
          message: 'Booking quote is missing, expired or does not match.',
        );
      } else {
        final ride = _ride(body, requestId);
        rides[ride['id'] as String] = ride;
        payload = {'code': 'OK', 'ride': ride, 'requestId': requestId};
      }
    } else if (parts.length == 6 &&
        parts[1] == 'api' &&
        parts[3] == 'rides' &&
        parts.last == 'feedback' &&
        method == 'POST') {
      final ride = rides[parts[4]];
      final rating = body['rating'];
      final tipMinor = body['tipMinor'];
      if (ride == null) {
        status = 404;
        payload = _error('not_found', requestId);
      } else if (!_rateable(ride, parts[4])) {
        status = 409;
        payload = _error(
          'invalid_transition',
          requestId,
          reason: 'ride_not_complete',
          projection: ride,
        );
      } else if ((rating == null && tipMinor == null) ||
          // Q38 / X20: whole stars only (1 to 5); 0.5 steps are refused.
          (rating != null && (rating is! num || rating < 1 || rating > 5 || rating != rating.roundToDouble())) ||
          (tipMinor != null && (tipMinor is! int || tipMinor <= 0 || tipMinor > 999900 || body['currency'] != _currencyOf(ride)))) {
        status = 400;
        payload = _error('invalid_request', requestId, reason: 'invalid_feedback');
      } else {
        ride['feedback'] = {
          if (rating != null) 'rating': rating,
          if (tipMinor != null) 'tipMinor': tipMinor,
          if (tipMinor != null) 'currency': _currencyOf(ride),
        };
        if (rating != null) {
          // ratingTransitions: (not_requested →) pending → submitted.
          ride['ratingStatus'] = TripRatingStatus.submitted.wireName;
          _touch(ride, 'rating_updated');
        }
        payload = {'code': 'OK', 'status': 'accepted', 'requestId': requestId};
      }
    } else if (parts.length >= 6 &&
        parts[1] == 'api' &&
        parts[3] == 'rides' &&
        parts.last == 'disputes' &&
        method == 'POST') {
      final id = parts[4];
      final reason = body['reason'];
      if (reason is! String || reason.trim().isEmpty) {
        status = 400;
        payload = _error('invalid_request', requestId, reason: 'invalid_dispute');
      } else {
        payload = {
          'code': 'OK',
          'dispute': {
            'rideId': id,
            'reason': reason,
            if (body['detail'] is String) 'detail': body['detail'],
            'status': 'submitted',
          },
          'requestId': requestId,
        };
      }
    } else if (parts.length == 6 &&
        parts[1] == 'api' &&
        parts[3] == 'trips' &&
        parts.last == 'cancel-reason' &&
        method == 'POST') {
      // Contract v0.4.4 §3 "After-cancel reason" (owner decision 6). Not a
      // transition: only cancellation.reasonCode / note change, no version,
      // sequence, updatedAt or fee change, and no realtime event.
      final ride = rides[parts[4]];
      final reasonCode = body['reasonCode'];
      final note = body['note'];
      final cancellation = ride?['cancellation'];
      if (ride == null) {
        status = 404;
        payload = _error('not_found', requestId);
      } else if (!CancelReasonCodes.isRiderCode(reasonCode) ||
          (note != null && (note is! String || note.length > 1000))) {
        status = 400;
        payload = _invalidReason(reasonCode, TripActor.rider, requestId);
      } else if (_statusOf(ride) != TripStatus.cancelledByRider ||
          cancellation is! Map ||
          cancellation['reasonCode'] != CancelReasonCodes.unspecified) {
        status = 409;
        payload = _invalidTransition(ride, 'cancel_reason', requestId);
      } else {
        cancellation['reasonCode'] = reasonCode;
        if (note is String) cancellation['note'] = note;
        // The pre-v0.3 field the app's History and older tests read.
        ride['cancellationReason'] = reasonCode;
        payload = {'code': 'OK', 'ride': ride, 'requestId': requestId};
      }
    } else if (parts.length >= 6 &&
        parts[1] == 'api' &&
        parts[3] == 'rides' &&
        (parts.last == 'cancel' || parts.last == 'end-early') &&
        method == 'POST') {
      final id = parts[4];
      final ride = rides[id];
      final command = parts.last == 'end-early' ? 'end_early' : 'cancel';
      final reasonCode = body['reasonCode'];
      if (ride == null) {
        status = 404;
        payload = _error('not_found', requestId);
      } else if (reasonCode != null &&
          !_reasonAllowed(reasonCode, command, TripActor.rider)) {
        // X7: a reason code outside the rider group (contract.json
        // #cancelReasons) is refused, never stored.
        status = 400;
        payload = _invalidReason(reasonCode, TripActor.rider, requestId);
      } else if (command == 'cancel' && reasonCode == null) {
        // rider-u19: openapi `CancelCommand` requires `reasonCode`, and a
        // validation error is `400 invalid_request` (CONTRACT §1). Accepting
        // a cancel without one hid that the app never sent it.
        status = 400;
        payload = _error(
          'invalid_request',
          requestId,
          reason: 'reason_code_required',
          message: 'reasonCode is required.',
        );
      } else if (_statusOf(ride) == TripStatus.cancelledByRider) {
        // Contract v0.4.4 (owner decision 6): a second cancel of a
        // cancelled trip is 409 invalid_transition with the projection, as
        // the table says; it never changes the reason (that is
        // POST /trips/{id}/cancel-reason below). It is checked before the
        // version, so a stale repeat still gets the projection, which the
        // app reads as "already cancelled" (R-O3, client side).
        status = 409;
        payload = _invalidTransition(ride, command, requestId);
      } else if (_versionMismatch(ride, body, requestId) case final stale?) {
        status = 409;
        payload = stale;
      } else {
        // `cancel` before boarding, `end_early` once the rider is on board
        // (POST .../end-early); anything else is invalid_transition.
        // The fee is worked out before the command clears the driver.
        final fee = command == 'cancel' ? _riderCancelFee(ride) : null;
        // R-O1: an end-early trip costs the distance driven at the
        // category's rates, priced before the command changes the trip.
        final endEarlyFare = command == 'end_early'
            ? _endEarlyFare(ride)
            : null;
        if (!_apply(ride, command, TripActor.rider)) {
          status = 409;
          payload = _invalidTransition(ride, command, requestId);
        } else {
          // A cancel-first names the unspecified code only (rider-u19): the
          // rider picked no reason yet, and the one they pick afterwards
          // comes with POST /trips/{id}/cancel-reason (v0.4.4).
          final reason = body['reason'] ??
              (reasonCode == CancelReasonCodes.unspecified ? null : reasonCode);
          if (reason is String) ride['cancellationReason'] = reason;
          ride['cancellation'] = {
            'actor': TripActor.rider.wireName,
            // openapi Cancellation requires a code; an end-early names none.
            'reasonCode': reasonCode is String
                ? reasonCode
                : CancelReasonCodes.unspecified,
            'at': ride['updatedAt'],
            // Contract §6: the live or reservation FeeRule of the trip's
            // category; null when free. End-early is not a cancel fee: the
            // rider pays the trip's `fare` for the distance driven.
            'fee': fee?.toJson(),
          };
          if (endEarlyFare != null) {
            ride['fare'] = endEarlyFare.fare.toJson();
            ride['fareLines'] = [
              {'code': 'base', 'amount': endEarlyFare.base.toJson()},
              {'code': 'distance', 'amount': endEarlyFare.distance.toJson()},
            ];
            // R-O6 (owner decision): the rider rates an ended-early trip on
            // the normal trip-end screen. See [_endedEarly].
            _endedEarly.add(id);
            ride['ratingStatus'] = TripRatingStatus.pending.wireName;
          }
          payload = {'code': 'OK', 'ride': ride, 'requestId': requestId};
        }
      }
    } else if (parts.length >= 6 &&
        parts[1] == 'api' &&
        parts[3] == 'rides' &&
        parts.last == 'nearby' &&
        method == 'GET') {
      final id = parts[4];
      payload = {
        'code': 'OK',
        'vehicles': _nearby(rides[id]),
        'requestId': requestId,
      };
    } else if (parts.length >= 6 &&
        parts[1] == 'api' &&
        parts[3] == 'rides' &&
        parts.last == 'status' &&
        method == 'POST') {
      // Stand-in for the driver app and dispatch (demo/test only, not part
      // of the shared contract). Body: `{command, actor}` for one command,
      // or `{status}` (a contract name, or a legacy Rider name) to walk the
      // trip there one legal driver/system transition at a time, and/or
      // `{paymentStatus}` / `{ratingStatus}` after completion. Nothing here
      // bypasses the transition table.
      final ride = rides[parts[4]];
      final simulatedActor =
          TripActorWire.parse(body['actor']) ?? TripActor.driver;
      final simulatedReason = body['reasonCode'];
      if (ride == null) {
        status = 404;
        payload = _error('not_found', requestId);
      } else if (_versionMismatch(ride, body, requestId) case final stale?) {
        status = 409;
        payload = stale;
      } else if (simulatedReason != null &&
          (body['command'] is! String ||
              !_reasonAllowed(
                simulatedReason,
                body['command'] as String,
                simulatedActor,
              ))) {
        status = 400;
        payload = _invalidReason(simulatedReason, simulatedActor, requestId);
      } else {
        final denied = _simulate(ride, body);
        if (denied != null) {
          status = 409;
          payload = _invalidTransition(ride, denied, requestId);
        } else {
          if (simulatedReason is String && ride['cancellation'] is Map) {
            (ride['cancellation'] as Map)['reasonCode'] = simulatedReason;
          }
          if (body['driver'] is Map) ride['driver'] = body['driver'];
          if (body['lat'] != null) ride['driverLat'] = body['lat'];
          if (body['lng'] != null) ride['driverLng'] = body['lng'];
          _trackDriven(ride, body['lat'], body['lng']);
          if (body['lat'] != null && body['command'] == null &&
              body['status'] == null) {
            // A GPS fix alone: a `location` event, version unchanged.
            ride['locationAt'] = DateTime.now().toUtc().toIso8601String();
            _sequenceEvent(ride, 'location');
          }
          payload = {'code': 'OK', 'ride': ride, 'requestId': requestId};
        }
      }
    } else if (parts.length == 6 &&
        parts[1] == 'api' &&
        parts[3] == 'rides' &&
        parts.last == 'route-quote' &&
        method == 'POST') {
      // Prices a route change (new pickup, destination or stops) without
      // applying it, so the rider sees the new price before confirming.
      final ride = rides[parts[4]];
      if (ride == null) {
        status = 404;
        payload = _error('not_found', requestId);
      } else if (_versionMismatch(ride, body, requestId) case final stale?) {
        // R-O2: a route quote is asked for the trip the rider sees.
        status = 409;
        payload = stale;
      } else {
        final denied = _routeChangeDenied(ride, body);
        if (denied != null) {
          status = 409;
          payload = _routeChangeError(denied, ride, requestId);
        } else {
          final pricing = _routeChangePricing(ride, body);
          final quoteId = 'rq_${newRequestId()}';
          final expiresAt = DateTime.now()
              .add(const Duration(minutes: 5))
              .toUtc()
              .toIso8601String();
          final newTotalMinor = pricing['newMinor'] as int;
          routeQuotes[quoteId] = {
            'rideId': parts[4],
            'route': _routeFingerprint(body),
            'expiresAt': expiresAt,
            'newTotalMinor': newTotalMinor,
          };
          payload = {
            'code': 'OK',
            ..._pricingWire(pricing),
            'routeQuoteId': quoteId,
            'expiresAt': expiresAt,
            'requestId': requestId,
          };
        }
      }
    } else if (parts.length == 5 &&
        parts[1] == 'api' &&
        parts[3] == 'rides' &&
        method == 'PATCH') {
      final id = parts[4];
      final ride = rides[id];
      final routeChange = body['routeChange'] == true;
      if (ride == null) {
        status = 404;
        payload = _error('not_found', requestId);
      } else if (_versionMismatch(ride, body, requestId) case final stale?) {
        // R-O2: a route, pickup or offer change made on a stale screen.
        status = 409;
        payload = stale;
      } else if (routeChange) {
        final denied =
            _routeChangeDenied(ride, body) ?? _routeQuoteDenied(id, ride, body);
        if (denied != null) {
          status = 409;
          payload = _routeChangeError(denied, ride, requestId);
        } else {
          final pricing = _routeChangePricing(ride, body);
          final movedStatus = _statusOf(ride);
          final moved = body['pickupAddress'] != null &&
                  body['pickupAddress'] != ride['pickupAddress'] &&
                  (movedStatus == TripStatus.accepted ||
                      movedStatus == TripStatus.driverToPickup)
              ? _pickupMoveMeters(ride, body)
              : null;
          if (body['pickupAddress'] != null) {
            ride['pickupAddress'] = body['pickupAddress'];
            ride['pickupLat'] = body['pickupLat'];
            ride['pickupLng'] = body['pickupLng'];
          }
          ride['destinationAddress'] = body['destinationAddress'];
          ride['destinationLat'] = body['destinationLat'];
          ride['destinationLng'] = body['destinationLng'];
          _withPlaces(ride);
          ride['stops'] = pricing['stops'];
          final newMinor = pricing['newMinor'] as int;
          final rideCurrency = _currencyOf(ride);
          _setFare(ride, newMinor);
          ride['maxOfferMinor'] = _maxOfferMinorFor(newMinor, rideCurrency);
          _touch(ride);
          // The driver app is told on its next poll; the log is what admin
          // reads later.
          ride['driverNotifiedAt'] = ride['updatedAt'];
          if (moved != null) {
            // Q40: the driver is told the accepted pickup moved, on the
            // same next-poll path.
            (ride['driverNotices'] ??= <Map<String, dynamic>>[]).add({
              'kind': 'pickup_moved',
              'at': ride['updatedAt'],
              'meters': moved.round(),
              'pickupAddress': body['pickupAddress'],
            });
          }
          // Cash only shows the new price; any other method is
          // charged or refunded the difference right away.
          // ARCH-9: the method id decides; the label is the old contract.
          final methodId = body['paymentMethodId']?.toString();
          final method =
              (methodId ?? body['paymentMethod'] ?? '').toString();
          final cash = methodId != null
              ? methodId == 'cash'
              : method.toLowerCase() == 'cash' ||
                    method.toLowerCase().contains('pay in car');
          final difference = pricing['differenceMinor'] as int;
          // Half a major unit or more (50 öre, 50 cents, 500 millimes).
          if (!cash &&
              difference.abs() * 2 >= Money.minorPerMajor(rideCurrency)) {
            (ride['paymentAdjustments'] ??= <Map<String, dynamic>>[]).add({
              'at': ride['updatedAt'],
              'method': method,
              'amount': _money(difference, rideCurrency),
              'status': difference > 0 ? 'captured' : 'refunded',
              if (difference < 0)
                // wallet: credited at once; originalMethod: 2–3 business days.
                'refundTo': body['refundTo']?.toString() ?? 'originalMethod',
            });
          }
          (ride['routeChanges'] ??= <Map<String, dynamic>>[]).add({
            'at': ride['updatedAt'],
            'destinationAddress': body['destinationAddress'],
            'stops': pricing['stops'],
            'newTotal': _money(newMinor, rideCurrency),
            'difference': _money(difference, rideCurrency),
          });
          payload = {
            'code': 'OK',
            'ride': ride,
            ..._pricingWire(pricing),
            'requestId': requestId,
          };
        }
      } else {
        final current = _statusOf(ride);
        final searching = current == TripStatus.requested ||
            current == TripStatus.searching ||
            current == TripStatus.offered;
        if (!searching) {
          status = 409;
          payload = _error(
            'invalid_transition',
            requestId,
            reason: 'ride_not_searching',
            message: 'Ride can only be edited while searching',
            projection: ride,
          );
        } else if ((body.containsKey('offerIncrease') ||
                body.containsKey('offerIncreaseKr')) &&
            _offerIncreaseMinor(body, _currencyOf(ride)) == null) {
          status = 422;
          payload = _error(
            'invalid_request',
            requestId,
            reason: 'invalid_offer',
            message: 'Offer increase must be a positive whole amount',
          );
        } else if (_offerAboveMaximum(
          ride,
          _offerIncreaseMinor(body, _currencyOf(ride)),
        )) {
          // ARCH-20: the ceiling holds on the server, whatever the client
          // computed after a reload.
          status = 409;
          payload = _error(
            'conflict',
            requestId,
            reason: 'offer_above_maximum',
            message: 'Offer is above the maximum for this ride',
            projection: ride,
          );
        } else {
          // D-012: the server prices an offer bump itself from the rider's
          // intent (offerIncreaseKr). A client-sent `price` is never treated
          // as authority and is ignored. The ceiling is checked above.
          final rideCurrency = _currencyOf(ride);
          final increase = _offerIncreaseMinor(body, rideCurrency);
          final fare = _fareMinor(ride);
          if (increase != null && fare != null) {
            _setFare(ride, fare + increase);
            ride['offerIncrease'] = _money(increase, rideCurrency);
            // rider-u14: every raise, kept for route-change pricing.
            ride['offerRaised'] = _money(
              _offerRaisedMinor(ride) + increase,
              rideCurrency,
            );
          }
          if (body['pickupAddress'] != null) {
            ride['pickupAddress'] = body['pickupAddress'];
          }
          if (body['pickupLat'] != null) ride['pickupLat'] = body['pickupLat'];
          if (body['pickupLng'] != null) ride['pickupLng'] = body['pickupLng'];
          if (body['destinationAddress'] != null) {
            ride['destinationAddress'] = body['destinationAddress'];
          }
          if (body['destinationLat'] != null) {
            ride['destinationLat'] = body['destinationLat'];
          }
          if (body['destinationLng'] != null) {
            ride['destinationLng'] = body['destinationLng'];
          }
          _withPlaces(ride);
          payload = {'code': 'OK', 'ride': ride, 'requestId': requestId};
        }
      }
    } else if (path.startsWith('/api/v1/rides/') &&
        method == 'GET' &&
        parts.length == 5) {
      final id = parts.last;
      final ride = rides[id];
      if (ride == null) {
        status = 404;
        payload = _error('not_found', requestId);
      } else {
        _expireSearchIfDue(ride);
        payload = {
          'code': 'OK',
          'ride': ride,
          // The last committed event, envelope-style (contract §4).
          'eventId': ride['eventId'],
          'sequence': ride['sequence'],
          'kind': ride['eventKind'],
          'serverTime': DateTime.now().toUtc().toIso8601String(),
          'requestId': requestId,
        };
      }
    } else if (path == '/api/v1/payments' && method == 'POST') {
      final amountMinor = body['amountMinor'];
      // Q8: a zone currency (one wallet per currency, a top-up in each).
      final currency = Money.normalizeCurrency(body['currency']);
      if (amountMinor is! int ||
          amountMinor <= 0 ||
          currency == null ||
          RiderZones.byCurrency(currency) == null) {
        status = 400;
        payload = _error(
          'invalid_request',
          requestId,
          reason: 'invalid_payment_intent',
        );
      } else {
        final intent = <String, dynamic>{
          'id': 'pi_$requestId',
          'status': 'requires_confirmation',
          'amountMinor': amountMinor,
          'currency': currency,
          // C-10 (PROPOSED): what the intent pays for.
          if (body['purpose'] is String) 'purpose': body['purpose'],
          if (body['rideId'] is String) 'rideId': body['rideId'],
        };
        paymentIntents[intent['id'] as String] = intent;
        payload = {
          'code': 'OK',
          'intent': Map<String, dynamic>.from(intent),
          'requestId': requestId,
        };
      }
    } else if (parts.length == 6 &&
        parts[1] == 'api' &&
        parts[3] == 'payments' &&
        parts.last == 'confirm' &&
        method == 'POST') {
      final intent = paymentIntents[parts[4]];
      if (intent == null) {
        status = 404;
        payload = _error('not_found', requestId, reason: 'payment_not_found');
      } else {
        intent['status'] = 'succeeded';
        payload = {
          'code': 'OK',
          'status': 'succeeded',
          'intent': Map<String, dynamic>.from(intent),
          'requestId': requestId,
        };
      }
    } else if (parts.length == 5 &&
        parts[1] == 'api' &&
        parts[3] == 'payments' &&
        method == 'GET') {
      final intent = paymentIntents[parts[4]];
      if (intent == null) {
        status = 404;
        payload = _error('not_found', requestId, reason: 'payment_not_found');
      } else {
        payload = {
          'code': 'OK',
          'status': intent['status'],
          'intent': Map<String, dynamic>.from(intent),
          'requestId': requestId,
        };
      }
    } else if (path == '/api/v1/wallet/topup' && method == 'POST') {
      payload = {
        'code': 'OK',
        'status': 'succeeded',
        'amountMinor': body['amountMinor'] ?? 0,
        'currency': currency,
        'requestId': requestId,
      };
    } else if (path == '/api/v1/ride-types' && method == 'GET') {
      payload = {
        'code': 'OK',
        'rideTypes': rideTypes
            .map((type) => Map<String, dynamic>.from(type))
            .toList(),
        'requestId': requestId,
      };
    } else if (path == '/api/v1/rider/promotions/active' && method == 'GET') {
      // Demo transport only: a sample admin promotion so the ticket can be
      // seen on GitHub Pages. The live API returns the rider's real one.
      payload = {
        'code': 'OK',
        'promotion': activePromotion,
        'requestId': requestId,
      };
    } else if (path == '/api/v1/rider/scheduled-rides/rules' &&
        method == 'GET') {
      // PROPOSED: the admin-set free-cancel window, late-cancel fee and
      // driver reveal for Book for later.
      payload = {
        'code': 'OK',
        'rules': Map<String, dynamic>.from(scheduledRideRules),
        'requestId': requestId,
      };
    } else if (path == '/api/v1/rider/profile' && method == 'GET') {
      // rider-u148: the profile the server holds, or null for a rider who
      // has none yet.
      payload = {
        'code': 'OK',
        'profile': riderProfile,
        'requestId': requestId,
      };
    } else if (path == '/api/v1/rider/profile' && method == 'PATCH') {
      // FLOW-7 / C-12 (PROPOSED): name, language and consents. A field left
      // out keeps the value the server holds (rider-u148).
      final name = body['name'];
      final consents = body['consents'];
      if ((name != null && (name is! String || name.trim().length > 80)) ||
          (consents != null && consents is! Map)) {
        status = 422;
        payload = _error('invalid_request', requestId, reason: 'invalid_profile');
      } else {
        final previous = riderProfile;
        riderProfile = {
          ...?previous,
          if (name is String) 'name': name.trim(),
          if (body['language'] is String) 'language': body['language'],
          'consents': {
            ...?(previous?['consents'] as Map?),
            ...?(consents as Map?),
          },
        };
        payload = {
          'code': 'OK',
          'profile': riderProfile,
          'requestId': requestId,
        };
      }
    } else if (path == '/api/v1/rider/trips/active' && method == 'GET') {
      // ARCH-12 / C-5 (PROPOSED): the rider's live trip, or none.
      Map<String, dynamic>? live;
      for (final ride in rides.values) {
        if (_statusOf(ride).isTerminal || ride['scheduledAt'] != null) {
          continue;
        }
        live = ride;
      }
      payload = {'code': 'OK', 'trip': live, 'requestId': requestId};
    } else if (path == '/api/v1/rider/trips' && method == 'GET') {
      // ARCH-12 / C-5 (PROPOSED): finished trips, newest first, one page.
      final finished = [
        for (final ride in rides.values.toList().reversed)
          if (_statusOf(ride).isTerminal) ride,
      ];
      payload = {
        'code': 'OK',
        'trips': finished,
        'nextCursor': null,
        'requestId': requestId,
      };
    } else if (path == '/api/v1/payment-methods' && method == 'GET') {
      // ARCH-7 / C-10 (PROPOSED). Cards would be PSP-tokenised methods.
      payload = {
        'code': 'OK',
        'methods': const [
          {'id': 'wallet', 'kind': 'wallet', 'label': 'Movera Wallet'},
          {'id': 'apple', 'kind': 'applePay', 'label': 'Apple Pay'},
          {'id': 'google', 'kind': 'googlePay', 'label': 'Google Pay'},
          {'id': 'cash', 'kind': 'cash', 'label': 'Cash'},
        ],
        'defaultMethodId': defaultPaymentMethodId,
        'requestId': requestId,
      };
    } else if (path == '/api/v1/payment-methods/default' &&
        method == 'PATCH') {
      final methodId = body['methodId'];
      if (methodId is! String || methodId.trim().isEmpty) {
        status = 422;
        payload = _error('invalid_request', requestId, reason: 'invalid_payment_method');
      } else {
        defaultPaymentMethodId = methodId.trim();
        payload = {
          'code': 'OK',
          'defaultMethodId': defaultPaymentMethodId,
          'requestId': requestId,
        };
      }
    } else if (path == '/health' && method == 'GET') {
      payload = {'ok': true, 'requestId': requestId};
    } else {
      if (persistSafety) await safety.restoreOnce();
      final safetyHit = safety.handle(
        method: method,
        path: path,
        body: body,
        requestId: requestId,
      );
      if (safetyHit != null) {
        status = safetyHit.status;
        payload = safetyHit.payload;
        if (persistSafety && method != 'GET' && status < 400) {
          await safety.persist();
        }
      } else {
        status = 404;
        payload = _error('not_found', requestId, message: 'No route for $path');
      }
    }

    if (replayKey != null && status < 400) {
      idempotency[replayKey] = IdempotentReplay(
        body: bodyKey,
        response: jsonEncode(payload),
        at: _clock(),
      );
    }
    return _json(status, payload, requestId);
  }

  void _evictIdempotency() {
    final cutoff = _clock().subtract(idempotencyTtl);
    idempotency.removeWhere((_, replay) => replay.at.isBefore(cutoff));
    while (idempotency.length > idempotencyLimit) {
      idempotency.remove(idempotency.keys.first);
    }
  }

  /// Demo-only places around Södertälje and Stockholm (and a few in Paris
  /// and Tunis), so address search can be tried on GitHub Pages. The live
  /// API searches real addresses.
  static const List<(String, String, double, double)> _demoPlaces = [
    ('Klockarvägen 37', '151 59 Södertälje', 59.1955, 17.6253),
    ('Klockarvägen 98', 'Södertälje', 59.1949, 17.6301),
    ('Klockarvägen 104', 'Södertälje', 59.1946, 17.6318),
    ('Klockarvägen 110', 'Södertälje', 59.1941, 17.6336),
    ('Klostergatan 3', 'Södertälje', 59.1991, 17.6262),
    ('Albyvägen 5', '145 59 Norsborg', 59.2448, 17.8562),
    ('Alby Centrum', 'Albyvägen 6, Norsborg', 59.2393, 17.8457),
    ('Drottninggatan 5', '111 51 Stockholm', 59.3326, 18.0649),
    ('Drottninggatan 5', '753 10 Uppsala', 59.8586, 17.6389),
    ('Stockholm Central', 'Centralplan 15, Stockholm', 59.3303, 18.0590),
    ('Stockholm Arlanda Airport', 'Arlanda', 59.6498, 17.9238),
    ('Arlanda Airport Terminal 5', 'Arlanda', 59.6519, 17.9297),
    ('Södertälje Centrum', 'Storgatan, Södertälje', 59.1960, 17.6260),
    ('Svarvarvägen 5', '142 50 Stockholm', 59.2089, 17.9466),
    ('Mall of Scandinavia', 'Stjärntorget 2, Solna', 59.3700, 18.0050),
    // Q7: places in the Paris Centre and Tunis Centre zones, so a demo trip
    // can be priced in euros or dinars.
    ('Gare du Nord', '18 Rue de Dunkerque, Paris', 48.8809, 2.3553),
    ('Musée du Louvre', 'Rue de Rivoli, Paris', 48.8606, 2.3376),
    ('Avenue Habib Bourguiba', 'Tunis', 36.8008, 10.1865),
    ('Médina de Tunis', 'Tunis', 36.7983, 10.1700),
  ];

  static String _fold(String value) {
    const from = 'åäöéèêëàâüïîôç';
    const to = 'aaoeeeeaauiioc';
    final out = StringBuffer();
    for (final char in value.toLowerCase().split('')) {
      final i = from.indexOf(char);
      out.write(i < 0 ? char : to[i]);
    }
    return out.toString();
  }

  List<Map<String, dynamic>> _demoSuggestions(
    String query, {
    bool typedFallback = true,
  }) {
    final words = _fold(query.trim()).split(RegExp(r'[\s,]+'))
      ..removeWhere((w) => w.isEmpty);
    if (words.isEmpty) return const [];
    final found = <Map<String, dynamic>>[];
    for (final (title, subtitle, lat, lng) in _demoPlaces) {
      final hay = _fold('$title $subtitle');
      final tokens = hay.split(RegExp(r'[\s,]+'));
      final all = words.every(
        (w) => tokens.any((t) => t.startsWith(w)) || hay.contains(w),
      );
      if (!all) continue;
      found.add({
        'title': title,
        'subtitle': subtitle,
        'latitude': lat,
        'longitude': lng,
      });
    }
    // Anything else typed is still offered, so demo bookings always work.
    final typed = query.trim();
    if (typedFallback && typed.length >= 3 && found.isEmpty) {
      final hash = _fold(typed).codeUnits.fold<int>(
        0,
        (value, unit) => ((value * 31) + unit) & 0x7fffffff,
      );
      found.add({
        'title': typed,
        'subtitle': 'Sweden',
        'latitude': 59.3293 + (((hash % 1201) - 600) / 100000.0),
        'longitude': 18.0686 + ((((hash ~/ 1201) % 1601) - 800) / 100000.0),
      });
    }
    return found.take(8).toList();
  }

  void _expireSearchIfDue(Map<String, dynamic> ride) {
    final current = _statusOf(ride);
    if (current != TripStatus.searching && current != TripStatus.offered) {
      return;
    }
    final startedRaw = ride['searchStartedAt'];
    final started = startedRaw is String ? DateTime.tryParse(startedRaw) : null;
    if (started == null) return;
    final now = DateTime.now().toUtc();
    if (now.difference(started) < searchExpiresAfter) return;
    // `expire` (system): no driver found in time.
    _apply(ride, 'expire', TripActor.system);
  }

  /// The stored trip status. Stored rides carry a contract name; a legacy
  /// Rider name (tests that seed `rides[...]` by hand) is read through the
  /// UI → trip map once, then the trip is written back in contract form.
  static TripStatus _statusOf(Map<String, dynamic> ride) {
    final raw = ride['status'];
    final trip = TripStatusWire.parse(raw);
    if (trip != null) return trip;
    final legacy = RideStatusWire.legacyName(raw);
    return legacy?.tripStatus ?? TripStatus.draft;
  }

  static TripKind _kindOf(Map<String, dynamic> ride) =>
      TripKindWire.parse(ride['kind']) ??
      (ride['scheduledAt'] != null ? TripKind.scheduled : TripKind.live);

  /// One committed change: version + 1, new updatedAt, and the next
  /// server-assigned realtime `sequence` with a unique `eventId` and its
  /// event kind (contract v0.3.0 §4; clients never number events).
  static void _touch(
    Map<String, dynamic> ride, [
    String eventKind = 'trip_projection',
  ]) {
    ride['version'] = ((ride['version'] as num?)?.toInt() ?? 0) + 1;
    ride['updatedAt'] = DateTime.now().toUtc().toIso8601String();
    _sequenceEvent(ride, eventKind);
  }

  static void _sequenceEvent(Map<String, dynamic> ride, String eventKind) {
    final sequence = ((ride['sequence'] as num?)?.toInt() ?? 0) + 1;
    final id = (ride['tripId'] ?? ride['id']).toString();
    ride['sequence'] = sequence;
    ride['eventId'] = 'ev_${id}_$sequence';
    ride['eventKind'] = eventKind;
  }

  /// Applies [command] by [actor] through [TripStateMachine]. False (and
  /// nothing changed) when the table does not allow it.
  bool _apply(Map<String, dynamic> ride, String command, TripActor actor) {
    final from = _statusOf(ride);
    final to = TripStateMachine.apply(
      from,
      command,
      actor,
      kind: _kindOf(ride),
    );
    if (to == null) return false;
    ride['status'] = to.wireName;
    final tripId = (ride['tripId'] ?? ride['id']).toString();
    if (to == TripStatus.accepted) {
      final at = _clock();
      _acceptedAt[tripId] = at;
      // Contract v0.4.0 `TripProjection.acceptedAt` (Q12): the rider's
      // free-cancel clock counts from it.
      ride['acceptedAt'] = WireTime.format(at);
    } else if (to == TripStatus.searching || to == TripStatus.requested) {
      // Back in dispatch: the next accept starts a new free window.
      _acceptedAt.remove(tripId);
      ride['acceptedAt'] = null;
      ride.remove('waiting');
    }
    if (to == TripStatus.arrived) {
      // `TripProjection.waiting` (Q41/Q42): the waiting clock starts at
      // arrival; the category's free wait comes from the zone config.
      final at = _clock();
      final terms = _configFor(_currencyOf(ride)).waiting?.forCategory(
        (ride['categoryId'] ?? ride['rideType'] ?? '').toString(),
      );
      final freeUntil = at.add(Duration(minutes: terms?.freeWaitMin ?? 5));
      ride['waiting'] = {
        'arrivedAt': WireTime.format(at),
        'freeUntil': WireTime.format(freeUntil),
        'noShowAt': WireTime.format(
          at.add(Duration(minutes: terms?.noShowAfterMin ?? 5)),
        ),
        'chargedSeconds': 0,
      };
    }
    if (to == TripStatus.searching && from != TripStatus.offered) {
      // Back in dispatch (driver drop / admin reassign): the old driver is
      // gone and the search clock restarts.
      ride
        ..remove('driver')
        ..remove('driverLat')
        ..remove('driverLng');
      ride['searchStartedAt'] = DateTime.now().toUtc().toIso8601String();
    }
    if (to == TripStatus.completed) {
      // Payment and rating start as fields once the trip is done.
      ride['ratingStatus'] = TripRatingStatus.notRequested.wireName;
    }
    if (actor != TripActor.rider && to.isTerminal && to != TripStatus.completed) {
      ride['cancellation'] ??= {
        'actor': actor.wireName,
        // openapi Cancellation requires a code of the actor's group.
        'reasonCode': switch ((actor, command)) {
          (_, 'no_show') => 'rider_no_show',
          (TripActor.driver, _) => 'other_on_trip',
          (TripActor.admin, _) => 'admin_other',
          (_, 'expire') => 'system_no_driver',
          _ => 'system_error',
        },
        'at': DateTime.now().toUtc().toIso8601String(),
        'fee': null,
      };
    }
    _touch(
      ride,
      switch ((actor, command)) {
        (TripActor.rider, 'cancel' || 'end_early') => 'rider_cancelled',
        (TripActor.driver, 'cancel') => 'driver_cancelled',
        _ => 'trip_projection',
      },
    );
    return true;
  }

  /// `409 version_mismatch` with the projection when [body] carries an
  /// `expectedVersion` that is not the trip's current version (contract §1
  /// Concurrency). Null when it matches or is absent (pre-v0.3 clients).
  static Map<String, dynamic>? _versionMismatch(
    Map<String, dynamic> ride,
    Map<String, dynamic> body,
    String requestId,
  ) {
    final expected = body['expectedVersion'];
    if (expected == null) return null;
    final current = (ride['version'] as num?)?.toInt() ?? 0;
    if (expected is int && expected == current) return null;
    return {
      'code': 'version_mismatch',
      'message': 'The trip is at version $current, not $expected.',
      'requestId': requestId,
      'retryable': false,
      'projection': ride,
      'ride': ride,
    };
  }

  /// Whether [code] is a reason [actor] may give for [command]
  /// (`contract.json#cancelReasons`, by actor group).
  static bool _reasonAllowed(Object? code, String command, TripActor actor) {
    if (code is! String) return false;
    final groups = switch ((actor, command)) {
      (TripActor.rider, 'cancel' || 'end_early') => [CancelReasonCodes.rider],
      (TripActor.driver, 'no_show') => [CancelReasonCodes.noShow],
      (TripActor.driver, 'cancel') => [
        _driverBeforeTrip,
        _driverDuringTrip,
        _driverNextTrip,
        _driverScheduled,
      ],
      (TripActor.admin, _) => [CancelReasonCodes.admin],
      (TripActor.system, _) => [CancelReasonCodes.system],
      _ => const <List<String>>[],
    };
    return groups.any((group) => group.contains(code));
  }

  static const _driverBeforeTrip = [
    'rider_requested_cancel',
    'rider_not_at_pickup',
    'unsafe_pickup',
    'vehicle_issue_before_start',
    'driver_emergency_before_start',
    'other_before_start',
  ];
  static const _driverDuringTrip = [
    'rider_requested_early_end',
    'safety_concern_on_trip',
    'vehicle_issue_on_trip',
    'accident_or_road_emergency',
    'rider_behavior',
    'trip_or_destination_issue',
    'other_on_trip',
  ];
  static const _driverNextTrip = [
    'next_trip_current_running_late',
    'next_trip_pickup_too_far',
    'next_trip_rider_requested',
    'next_trip_vehicle_issue',
    'next_trip_driver_emergency',
    'next_trip_other',
  ];
  static const _driverScheduled = [
    'scheduled_cannot_make_time',
    'scheduled_vehicle_issue',
    'scheduled_personal_emergency',
    'scheduled_pickup_too_far',
    'scheduled_trip_details',
    'scheduled_other',
  ];

  /// Contract error body (`contract.json#errors`): `{code, message,
  /// requestId, retryable, projection?}` with a lower-case contract [code]
  /// (R-O4). [reason] is this stand-in's more specific cause in lower case
  /// (`otp_expired`, `pickup_locked`, …) beside it, not a contract field;
  /// clients fall back to [code] when a server sends none. `ride` is kept
  /// as the pre-v0.3 alias of `projection`.
  static Map<String, dynamic> _error(
    String code,
    String requestId, {
    String? reason,
    String? message,
    Map<String, dynamic>? projection,
  }) => {
    'code': code,
    'reason': ?reason,
    'message': message ?? reason ?? code,
    'requestId': requestId,
    'retryable':
        code == 'internal' || code == 'unavailable' || code == 'rate_limited',
    'projection': ?projection,
    'ride': ?projection,
  };

  /// A refused route change: a stage that no longer allows it is
  /// `invalid_transition`, a missing destination `invalid_request`, a
  /// route quote that no longer matches `conflict`; with the projection.
  static Map<String, dynamic> _routeChangeError(
    String reason,
    Map<String, dynamic> ride,
    String requestId,
  ) => _error(
    switch (reason) {
      'ride_finished' || 'pickup_locked' => 'invalid_transition',
      'destination_required' || 'pickup_too_far' => 'invalid_request',
      _ => 'conflict',
    },
    requestId,
    reason: reason,
    projection: ride,
  );

  static Map<String, dynamic> _invalidReason(
    Object? code,
    TripActor actor,
    String requestId,
  ) => {
    'code': 'invalid_request',
    'message': '$code is not a ${actor.wireName} cancel reason.',
    'requestId': requestId,
    'retryable': false,
  };

  /// `contract.json#ratingAllowed`: the rider rates a completed trip and
  /// one they ended early (R-O6), never a plain cancel.
  bool _rateable(Map<String, dynamic> ride, String tripId) {
    final status = _statusOf(ride);
    return TripRatingRules.allows(
      TripActor.rider,
      status,
      endedBy: _endedEarly.contains(tripId) ? 'end_early' : null,
    );
  }

  /// R-O1: adds the stretch from the last on-board fix to ([lat], [lng]).
  /// The first fix after boarding only marks where driving started.
  void _trackDriven(Map<String, dynamic> ride, Object? lat, Object? lng) {
    if (lat is! num || lng is! num) return;
    if (!tripRiderOnboardStatuses.contains(_statusOf(ride))) return;
    final tripId = (ride['tripId'] ?? ride['id']).toString();
    final last = _driven[tripId];
    final meters = last == null
        ? 0.0
        : last.meters + _km(last.lat, last.lng, lat, lng) * 1000;
    _driven[tripId] = (
      lat: lat.toDouble(),
      lng: lng.toDouble(),
      meters: meters,
    );
  }

  /// R-O1 (owner decision): what an ended-early trip costs. The rider pays
  /// for the distance driven at the category's own rates, the ones the
  /// quote engine below prices with ([MockCategoryRates]): base fare + km
  /// driven × per-km rate, in the currency's minor units. Never more than
  /// the trip's current fare. Null when the trip has no fare.
  ({Money fare, Money base, Money distance})? _endEarlyFare(
    Map<String, dynamic> ride,
  ) {
    final currentMinor = _fareMinor(ride);
    if (currentMinor == null) return null;
    final category = CategoryIds.canonical(
      (ride['categoryId'] ?? ride['rideType'] ?? '').toString(),
    );
    // Q7: in the trip's own currency, at the zone's rates.
    final code = _currencyOf(ride);
    final rates = _ratesFor(category, code);
    final tripId = (ride['tripId'] ?? ride['id']).toString();
    final meters = drivenMetersOf(tripId);
    final base = rates.baseFare;
    final distance = rates.distanceFare(meters);
    final total = base.amountMinor + distance.amountMinor;
    if (total <= currentMinor) {
      return (fare: Money(total, code), base: base, distance: distance);
    }
    // Capped at the agreed fare: ending early never costs more than the
    // whole trip (a detour, a promotion or a lower offer).
    final cappedDistance = math.max(0, currentMinor - base.amountMinor);
    return (
      fare: Money(currentMinor, code),
      base: Money(currentMinor - cappedDistance, code),
      distance: Money(cappedDistance, code),
    );
  }

  /// What a rider cancel costs now (contract §6 FeeRule, the shared
  /// calculator): live trips from the category's live rule, counted from
  /// the driver's accept (free before one accepted); scheduled trips from
  /// the reservation rule, counted to pickup (free once pickup passed with
  /// no driver). Null when free.
  Money? _riderCancelFee(Map<String, dynamic> ride) {
    final fareMinor = _fareMinor(ride);
    if (fareMinor == null) return null;
    // Q7: the fee rule of the trip's own zone, in its currency.
    final code = _currencyOf(ride);
    final config = _configFor(code);
    final fare = Money(fareMinor, code);
    final category = CategoryIds.canonical(
      (ride['categoryId'] ?? ride['rideType'] ?? '').toString(),
    );
    final now = _clock();
    Money? fee;
    if (_kindOf(ride) == TripKind.scheduled) {
      final rule = config.reservationFeeFor(category);
      final pickup = WireTime.tryParse(ride['scheduledAt']);
      if (rule == null || pickup == null) return null;
      if (ride['driver'] == null && !now.isBefore(pickup)) return null;
      fee = CancelFeeCalculator.reservation(
        rule,
        fare,
        pickup.difference(now).inMinutes,
      );
    } else {
      final rule = config.liveFeeFor(category);
      final accepted = _acceptedAt[(ride['tripId'] ?? ride['id']).toString()];
      if (rule == null || accepted == null) return null;
      fee = CancelFeeCalculator.live(
        rule,
        fare,
        now.difference(accepted).inMinutes,
      );
    }
    return fee.isPositive ? fee : null;
  }

  /// `409 invalid_transition` (contract errors shape) with the projection.
  /// `ride` is kept as the pre-v0.3 alias of `projection`.
  static Map<String, dynamic> _invalidTransition(
    Map<String, dynamic> ride,
    String command,
    String requestId,
  ) => {
    'code': 'invalid_transition',
    'message':
        '$command is not allowed while the trip is ${_statusOf(ride).wireName}.',
    'requestId': requestId,
    'retryable': false,
    'projection': ride,
    'ride': ride,
  };

  /// The demo simulator (see the `/status` route). Returns the refused
  /// command, or null when everything asked for was applied.
  String? _simulate(Map<String, dynamic> ride, Map<String, dynamic> body) {
    final command = body['command'];
    if (command is String) {
      final actor = TripActorWire.parse(body['actor']) ?? TripActor.driver;
      return _apply(ride, command, actor) ? null : command;
    }

    TripStatus? target;
    TripPaymentStatus? payment = TripPaymentStatusWire.parse(
      body['paymentStatus'],
    );
    TripRatingStatus? rating = TripRatingStatusWire.parse(body['ratingStatus']);
    final rawStatus = body['status'];
    if (rawStatus != null) {
      target = TripStatusWire.parse(rawStatus);
      final legacy = target == null ? RideStatusWire.legacyName(rawStatus) : null;
      if (legacy != null) {
        target = legacy.tripStatus;
        // Pre-v0.3 post-trip "statuses" are payment/rating fields now.
        switch (legacy) {
          case RideStatus.paymentProcessing:
            payment ??= TripPaymentStatus.authorized;
          case RideStatus.paymentFinalized:
            payment ??= TripPaymentStatus.captured;
          case RideStatus.ratingPending:
            payment ??= TripPaymentStatus.captured;
            rating ??= TripRatingStatus.pending;
          case RideStatus.closed:
            payment ??= TripPaymentStatus.captured;
            rating ??= TripRatingStatus.skipped;
          case RideStatus.paymentFailed:
            payment ??= TripPaymentStatus.failed;
          default:
            break;
        }
      }
      if (target == null) return 'status';
    }

    if (target != null && target != _statusOf(ride)) {
      final kind = _kindOf(ride);
      final path = TripStateMachine.pathTo(_statusOf(ride), target, kind: kind) ??
          TripStateMachine.pathTo(
            _statusOf(ride),
            target,
            kind: kind,
            actors: TripActor.values.toSet(),
          );
      if (path == null) return 'status:${target.wireName}';
      for (final (step, actor) in path) {
        if (!_apply(ride, step, actor)) return step;
      }
    }

    if (payment != null || rating != null) {
      if (_statusOf(ride) != TripStatus.completed) return 'settle';
      if (payment != null) {
        final current = TripPaymentStatusWire.parse(ride['paymentStatus']);
        final walk = _paymentWalk(current, payment);
        if (walk == null) return 'payment:${payment.wireName}';
        if (walk.isNotEmpty) {
          ride['paymentStatus'] = payment.wireName;
          _touch(ride, 'payment_updated');
        }
      }
      if (rating != null) {
        final current =
            TripRatingStatusWire.parse(ride['ratingStatus']) ??
            TripRatingStatus.notRequested;
        if (current != rating) {
          final allowed = tripRatingTransitions[current]?.contains(rating) ??
              false;
          final viaPending = current == TripRatingStatus.notRequested &&
              rating != TripRatingStatus.pending;
          if (!allowed && !viaPending) return 'rating:${rating.wireName}';
          ride['ratingStatus'] = rating.wireName;
          _touch(ride, 'rating_updated');
        }
      }
    }
    return null;
  }

  /// The payment statuses between [from] (null: no payment yet, which may
  /// start at `pending`) and [to] along `paymentTransitions`, or null.
  static List<TripPaymentStatus>? _paymentWalk(
    TripPaymentStatus? from,
    TripPaymentStatus to,
  ) {
    if (from == to) return const [];
    final start = from ?? TripPaymentStatus.pending;
    if (start == to) return [to];
    final previous = <TripPaymentStatus, TripPaymentStatus>{};
    final queue = [start];
    while (queue.isNotEmpty) {
      final at = queue.removeAt(0);
      for (final next in tripPaymentTransitions[at] ?? const <TripPaymentStatus>{}) {
        if (next == start || previous.containsKey(next)) continue;
        previous[next] = at;
        if (next == to) {
          final walk = <TripPaymentStatus>[to];
          var back = at;
          while (back != start) {
            walk.insert(0, back);
            back = previous[back]!;
          }
          return walk;
        }
        queue.add(next);
      }
    }
    return null;
  }

  /// How far (metres) [body] moves the trip's pickup, when both ends are
  /// known.
  static double? _pickupMoveMeters(
    Map<String, dynamic> ride,
    Map<String, dynamic> body,
  ) {
    final fromLat = ride['pickupLat'];
    final fromLng = ride['pickupLng'];
    final toLat = body['pickupLat'];
    final toLng = body['pickupLng'];
    if (fromLat is! num || fromLng is! num || toLat is! num || toLng is! num) {
      return null;
    }
    return GeoDistance.metersBetween(
      fromLat.toDouble(),
      fromLng.toDouble(),
      toLat.toDouble(),
      toLng.toDouble(),
    );
  }

  /// Pickup can move until the driver is at the door; the destination and
  /// the stops can change until the trip is over.
  String? _routeChangeDenied(
    Map<String, dynamic> ride,
    Map<String, dynamic> body,
  ) {
    final current = _statusOf(ride);
    if (current.isTerminal) return 'ride_finished';
    final pickupChanged =
        body['pickupAddress'] != null &&
        body['pickupAddress'] != ride['pickupAddress'];
    const pickupEditable = {
      TripStatus.requested,
      TripStatus.searching,
      TripStatus.offered,
      TripStatus.accepted,
      TripStatus.driverToPickup,
    };
    if (pickupChanged && !pickupEditable.contains(current)) {
      return 'pickup_locked';
    }
    // Q40: once a driver has accepted, the pickup moves only a short way.
    final moved = pickupChanged ? _pickupMoveMeters(ride, body) : null;
    if (moved != null &&
        moved > _configFor(_currencyOf(ride)).maxPickupMoveMeters &&
        (current == TripStatus.accepted ||
            current == TripStatus.driverToPickup)) {
      return 'pickup_too_far';
    }
    if (body['destinationLat'] is! num || body['destinationLng'] is! num) {
      return 'destination_required';
    }
    return null;
  }

  /// ARCH-20: true when [increaseMinor] would take the fare over the
  /// ceiling.
  static bool _offerAboveMaximum(Map<String, dynamic> ride, int? increaseMinor) {
    final max = ride['maxOfferMinor'];
    final fare = _fareMinor(ride);
    if (increaseMinor == null || max is! num || fare == null) return false;
    return fare + increaseMinor > max;
  }

  /// The highest fare a rider may offer for a ride priced [fareMinor] in
  /// [code]: 1.8×, in whole major units (kronor, euros, dinars).
  static int _maxOfferMinorFor(int fareMinor, String code) {
    final unit = Money.minorPerMajor(code);
    return (fareMinor * 1.8 / unit).round() * unit;
  }

  /// Money on the wire, in [code] (the home currency unless a trip or a
  /// zone says otherwise).
  static Map<String, Object> _money(int amountMinor, [String code = currency]) => {
    'amountMinor': amountMinor,
    'currency': code,
  };

  /// Q7: the currency of a stored trip, set at booking from its quote (the
  /// pickup's zone): its fare's, else its flat `currency`, else the home
  /// currency (a trip a test seeded by hand).
  static String _currencyOf(Map<String, dynamic> ride) {
    final fare = ride['fare'];
    final code = Money.normalizeCurrency(fare is Map ? fare['currency'] : null) ??
        Money.normalizeCurrency(ride['currency']);
    return code ?? currency;
  }

  /// Q7: the zone of the pickup a request names (`pickupLat`/`pickupLng`).
  static RiderZone _zoneOf(Map<String, dynamic> body) => RiderZones.at(
    (body['pickupLat'] as num?)?.toDouble(),
    (body['pickupLng'] as num?)?.toDouble(),
  );

  /// The stand-in's rates for [category] in [code] ([MockZoneRates]).
  MockZoneRates _ratesFor(String category, String code) => MockZoneRates(
    catalogKronor: _catalogPriceKr(category),
    currency: code,
  );

  /// The config document cancel fees are charged from for a trip in
  /// [code]: [riderConfig] when it is in that currency (tests replace it),
  /// else the seed of the zone with that currency.
  RiderAppConfig _configFor(String code) => riderConfig.currency == code
      ? riderConfig
      : SeedRiderConfigRepository.seedForCurrency(code) ?? riderConfig;

  /// The trip fare in minor units (`fare: Money`). A ride a test seeded
  /// with the pre-v0.3 whole-unit `price` is read once from it.
  static int? _fareMinor(Map<String, dynamic> ride) {
    final fare = ride['fare'];
    if (fare is Map && fare['amountMinor'] is int) {
      return fare['amountMinor'] as int;
    }
    final legacy = ride['price'];
    return legacy is num
        ? Money.fromLegacyMajor(legacy, _currencyOf(ride)).amountMinor
        : null;
  }

  /// The fare at booking, before offers and route changes.
  static int? _bookedMinor(Map<String, dynamic> ride) {
    final booked = ride['bookedFare'];
    if (booked is Map && booked['amountMinor'] is int) {
      return booked['amountMinor'] as int;
    }
    final legacy = ride['bookedPrice'];
    return legacy is num
        ? Money.fromLegacyMajor(legacy, _currencyOf(ride)).amountMinor
        : _fareMinor(ride);
  }

  /// rider-u14: every offer raise the rider made while searching, summed.
  static int _offerRaisedMinor(Map<String, dynamic> ride) {
    final raised = ride['offerRaised'];
    return raised is Map && raised['amountMinor'] is int
        ? raised['amountMinor'] as int
        : 0;
  }

  /// Contract money on the wire: `fare: Money` in the trip's currency,
  /// never whole-unit doubles.
  static void _setFare(Map<String, dynamic> ride, int amountMinor) {
    ride['fare'] = _money(amountMinor, _currencyOf(ride));
    ride.remove('price');
  }

  /// The rider's offer raise as minor units: `offerIncrease: Money` in the
  /// trip's currency [code], or the pre-v0.3 whole-kronor `offerIncreaseKr`
  /// (compatibility, kronor trips only). Null when it is not positive and
  /// on the zone's price step (a whole krona, 0.05 €, 0.1 DT).
  static int? _offerIncreaseMinor(Map<String, dynamic> body, String code) {
    final step = MockZoneCurrency.of(code).stepMinor;
    final money = body['offerIncrease'];
    if (money is Map) {
      final minor = money['amountMinor'];
      if (minor is int && minor > 0 && minor % step == 0 &&
          money['currency'] == code) {
        return minor;
      }
      return null;
    }
    final kr = body['offerIncreaseKr'];
    if (code == currency && kr is num && kr > 0 && kr == kr.roundToDouble()) {
      return Money.fromLegacyMajor(kr, code).amountMinor;
    }
    return null;
  }

  /// A route-change price on the wire: Money plus the flat minor fields
  /// (next to `currency`), no whole-unit doubles.
  static Map<String, Object?> _pricingWire(Map<String, dynamic> pricing) {
    final newMinor = pricing['newMinor'] as int;
    final differenceMinor = pricing['differenceMinor'] as int;
    final code = pricing['currency'] as String;
    return {
      'newTotal': _money(newMinor, code),
      'difference': _money(differenceMinor, code),
      'newTotalMinor': newMinor,
      'differenceMinor': differenceMinor,
      'currency': code,
      'routeKm': pricing['routeKm'],
      'stops': pricing['stops'],
    };
  }

  /// The route a route quote priced, to compare with the one applied.
  static String _routeFingerprint(Map<String, dynamic> body) => jsonEncode([
    body['pickupLat'],
    body['pickupLng'],
    body['destinationLat'],
    body['destinationLng'],
    [
      if (body['stops'] is List)
        for (final raw in body['stops'] as List)
          if (raw is Map) [raw['lat'], raw['lng']],
    ],
  ]);

  /// ARCH-14: an apply that names a route quote must match it: same ride,
  /// same route, not expired, and the price the rider confirmed is still the
  /// price. Without a route quote id the old contract still applies.
  String? _routeQuoteDenied(
    String rideId,
    Map<String, dynamic> ride,
    Map<String, dynamic> body,
  ) {
    final quoteId = body['routeQuoteId'];
    if (quoteId == null) return null;
    final quote = routeQuotes[quoteId];
    if (quote == null || quote['rideId'] != rideId) {
      return 'route_quote_not_found';
    }
    final expiresAt = DateTime.tryParse(quote['expiresAt'] as String? ?? '');
    if (expiresAt == null || !expiresAt.isAfter(DateTime.now())) {
      return 'route_quote_expired';
    }
    if (quote['route'] != _routeFingerprint(body)) {
      return 'route_quote_mismatch';
    }
    final quoted = quote['newTotalMinor'] as int;
    final expected = (body['expectedTotalMinor'] as num?)?.round();
    final now = _routeChangePricing(ride, body)['newMinor'] as int;
    if ((expected != null && expected != quoted) || now != quoted) {
      return 'route_quote_price_changed';
    }
    return null;
  }

  static double _km(num lat1, num lng1, num lat2, num lng2) {
    const r = 6371.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLng = (lng2 - lng1) * math.pi / 180;
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return 2 * r * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  /// New price for a changed route (contract §3 "Route-change pricing"):
  /// the booked price with the offer raises, plus 25 kr per stop that was
  /// not booked and 12 kr per kilometre beyond the booked route through its
  /// stops, in the trip's currency ([MockZoneRates]: 2.40 € and 1.15 € in Paris). Shorter routes
  /// get the difference back. Minor units, on the zone's price step.
  ///
  /// rider-9 / owner decision 5: a booked stop is counted once. The booked
  /// kilometres already go through it and the booking charged it no stop
  /// fee, so keeping it costs nothing more.
  ///
  /// rider-u14: the rider's offer raises are part of every new route's
  /// price, so a route change never takes back the raise the driver
  /// accepted.
  Map<String, dynamic> _routeChangePricing(
    Map<String, dynamic> ride,
    Map<String, dynamic> body,
  ) {
    final code = _currencyOf(ride);
    final rates = _ratesFor(
      (ride['categoryId'] ?? ride['rideType'] ?? '').toString(),
      code,
    );
    final baseMinor = (_bookedMinor(ride) ?? 0) + _offerRaisedMinor(ride);
    final pLat = (body['pickupLat'] ?? ride['pickupLat']) as num?;
    final pLng = (body['pickupLng'] ?? ride['pickupLng']) as num?;
    final dLat = body['destinationLat'] as num;
    final dLng = body['destinationLng'] as num;
    final stops = <Map<String, dynamic>>[
      if (body['stops'] is List)
        for (final raw in body['stops'] as List)
          if (raw is Map && raw['lat'] is num && raw['lng'] is num)
            {
              'address': raw['address']?.toString() ?? '',
              'lat': raw['lat'],
              'lng': raw['lng'],
            },
    ];
    final routeKm =
        _routedKm({
          'pickupLat': pLat,
          'pickupLng': pLng,
          'stops': stops,
          'destinationLat': dLat,
          'destinationLng': dLng,
        }) ??
        0;
    final bookedKm = (ride['bookedKm'] as num?)?.toDouble() ?? routeKm;
    final newMinor = rates.roundToStep(
      (baseMinor +
              _unbookedStops(ride, stops) * rates.convertKronor(25) +
              (routeKm - bookedKm) * rates.perKmMinor)
          .clamp(baseMinor * 0.5, double.infinity),
    );
    final currentMinor = _fareMinor(ride) ?? baseMinor;
    return {
      'newMinor': newMinor,
      'differenceMinor': newMinor - currentMinor,
      'currency': code,
      'routeKm': double.parse(routeKm.toStringAsFixed(2)),
      'stops': stops,
    };
  }

  /// The catalog price covers a trip this long ([MockCategoryRates]).
  static const _catalogTripMeters = MockCategoryRates.includedMeters;


  /// A stop this close to a booked stop is that booked stop (contract §3).
  static const _sameStopMeters = 50;

  /// How many of the new route's [stops] were not booked: each booked stop
  /// (`bookedStops`, else the trip's `stops`) matches one new stop within
  /// [_sameStopMeters], once.
  static int _unbookedStops(
    Map<String, dynamic> ride,
    List<Map<String, dynamic>> stops,
  ) {
    final bookedRaw = ride['bookedStops'] ?? ride['stops'];
    final booked = [
      if (bookedRaw is List)
        for (final raw in bookedRaw)
          if (raw is Map && raw['lat'] is num && raw['lng'] is num) raw,
    ];
    var unbooked = 0;
    for (final stop in stops) {
      final match = booked.indexWhere(
        (b) =>
            _km(b['lat'] as num, b['lng'] as num, stop['lat'] as num,
                    stop['lng'] as num) *
                1000 <=
            _sameStopMeters,
      );
      if (match < 0) {
        unbooked++;
      } else {
        booked.removeAt(match);
      }
    }
    return unbooked;
  }

  /// Pickup → stops → destination in metres, or null without the points.
  int? _routedMeters(Map<String, dynamic> body) {
    final km = _routedKm(body);
    return km == null ? null : math.max(1, (km * 1000).round());
  }

  /// Pickup → stops → destination in kilometres, or null without the points.
  static double? _routedKm(Map<String, dynamic> body) {
    final points = <List<num>>[];
    void add(Object? lat, Object? lng) {
      if (lat is num && lng is num) points.add([lat, lng]);
    }

    add(body['pickupLat'], body['pickupLng']);
    if (points.isEmpty) return null;
    if (body['stops'] is List) {
      for (final raw in body['stops'] as List) {
        if (raw is Map) add(raw['lat'], raw['lng']);
      }
    }
    final before = points.length;
    add(body['destinationLat'], body['destinationLng']);
    if (points.length == before) return null;
    var km = 0.0;
    for (var i = 1; i < points.length; i++) {
      km += _km(points[i - 1][0], points[i - 1][1], points[i][0], points[i][1]);
    }
    return km;
  }

  Map<String, dynamic> _quote(Map<String, dynamic> body) {
    // Contract v0.3.0: canonical category id; `movera` is read as `economy`.
    final rideType = CategoryIds.canonical(
      body['rideType'] as String? ?? CategoryIds.economy,
    );
    // ARCH-8 / contract C-2: price the route from the points (through the
    // stops) like a server would; the client's distance is only a hint for
    // callers that send no points.
    final distanceMeters =
        _routedMeters(body) ??
        (body['distanceMeters'] as num?)?.round() ??
        _catalogTripMeters;
    // Q7: the pickup's zone decides the currency, and the price is the
    // zone's own ([MockZoneRates]), not a converted kronor amount.
    final zone = _zoneOf(body);
    final rates = _ratesFor(rideType, zone.currency);
    final catalogMinor = rates.listMinor;
    final fullMinor = rates.quote(distanceMeters).amountMinor;
    // Demo promotion: discounts the ride types it names, capped per ride
    // (the cap is in kronor, so it is the zone's own amount elsewhere).
    final promo = activePromotion;
    final eligible =
        promo != null &&
        (promo['rideTypes'] as List? ?? const []).contains(rideType);
    final cap = (promo?['maxDiscountMinor'] as num?)?.round();
    final discountMinor = eligible
        ? ((fullMinor * (promo['percentOff'] as num) / 100).round()).clamp(
            0,
            cap == null
                ? fullMinor
                : rates.convertKronor(Money(cap, currency).major),
          )
        : 0;
    final minor = fullMinor - discountMinor;
    final id = 'q_${rideType}_${newRequestId()}';
    return {
      'id': id,
      'quoteId': id,
      'rideType': rideType,
      // Contract v0.3.0 Quote.total; the flat minor fields sit next to
      // `currency` for pre-v0.3 readers.
      'total': _money(minor, zone.currency),
      'totalMinor': minor,
      'amountMinor': minor,
      'currency': zone.currency,
      'zoneId': zone.id,
      // ARCH-11: RFC 3339 UTC with offset, like a real server.
      'expiresAt': WireTime.format(DateTime.now().add(const Duration(minutes: 2))),
      'expiresInSec': 120,
      'breakdown': {
        'baseMinor': math.min(fullMinor, catalogMinor),
        'distanceMinor': math.max(0, fullMinor - catalogMinor),
        'timeMinor': 0,
        'bookingFeeMinor': 0,
        'discountMinor': discountMinor,
      },
      'signedPayload': 'mock-api',
      'pickup': body['pickup'],
      'destination': body['destination'],
    };
  }

  String? _validateQuoteBinding(Map<String, dynamic> body) {
    // RIDE-22: a scheduled booking that carries a quote is held to it; one
    // without (the older contract) is still accepted.
    if (body['scheduledAt'] != null && body['quoteId'] == null) return null;
    if (body['pickupAddress'] == null) return null;

    final quoteId = body['quoteId'] as String?;
    final signed = body['quoteSignedPayload'] as String?;
    final expiryRaw = body['quoteExpiresAt'] as String?;
    final quotedTotal = (body['quoteTotalMinor'] as num?)?.round();
    if (quoteId == null ||
        quoteId.isEmpty ||
        signed == null ||
        signed.isEmpty ||
        expiryRaw == null ||
        quotedTotal == null) {
      return 'quote_required';
    }

    final quote = quotes[quoteId];
    if (quote == null) return 'quote_not_found';
    if (quote['signedPayload'] != signed) return 'quote_signature_mismatch';

    final expiresAt = DateTime.tryParse(expiryRaw);
    final serverExpiry = DateTime.tryParse(quote['expiresAt'] as String? ?? '');
    if (expiresAt == null ||
        serverExpiry == null ||
        expiresAt.toUtc() != serverExpiry.toUtc() ||
        !serverExpiry.isAfter(DateTime.now())) {
      return 'quote_expired';
    }

    final serverTotal = (quote['totalMinor'] as num?)?.round();
    if (serverTotal == null || serverTotal != quotedTotal) {
      return 'quote_amount_mismatch';
    }
    final quoteCurrency = (quote['currency'] as String?) ?? currency;

    final categoryId = CategoryIds.canonical((body['categoryId'] ?? '').toString());
    if (quote['rideType'] != categoryId) return 'quote_category_mismatch';

    // The fare the rider confirmed: `fare: Money` in the quote's currency,
    // or the pre-v0.3 whole-unit `price` (compatibility).
    final fare = body['fare'];
    if (fare is Map && fare['currency'] != quoteCurrency) {
      return 'quote_price_mismatch';
    }
    final submittedMinor = fare is Map && fare['amountMinor'] is int
        ? fare['amountMinor'] as int
        : (body['price'] is num
              ? Money.fromLegacyMajor(body['price'] as num, quoteCurrency)
                    .amountMinor
              : null);
    if (submittedMinor == null || submittedMinor != serverTotal) {
      return 'quote_price_mismatch';
    }

    // "Use wallet balance first" (contract C-3): the wallet part may not
    // exceed the fare, and is zero when the rider switched it off.
    final walletMinor = (body['walletAmountMinor'] as num?)?.round() ?? 0;
    final walletFirst = body['useWalletFirst'] == true;
    // Q8: one wallet per currency; the wallet part is in the trip's own
    // currency (the quote's minor units), never converted.
    if (walletMinor < 0 ||
        walletMinor > serverTotal ||
        (!walletFirst && walletMinor != 0)) {
      return 'wallet_amount_invalid';
    }

    return null;
  }

  Map<String, dynamic> _ride(Map<String, dynamic> body, String requestId) {
    final categoryId = CategoryIds.canonical(
      (body['categoryId'] ?? body['rideType'] ?? CategoryIds.economy).toString(),
    );
    final paymentMethodId =
        (body['paymentMethodId'] ?? body['paymentMethod'] ?? 'wallet').toString();
    final scheduled = body['scheduledAt'] != null;
    // The server walks the new trip draft → quoted → requested (→ searching
    // for a live trip) through the transition table; the client reads the
    // status from this response and never assumes it.
    var tripStatus = TripStatus.draft;
    for (final (command, actor) in [
      ('quote', TripActor.system),
      ('request', TripActor.rider),
      if (!scheduled) ('start_search', TripActor.system),
    ]) {
      tripStatus = TripStateMachine.apply(
        tripStatus,
        command,
        actor,
        kind: scheduled ? TripKind.scheduled : TripKind.live,
      )!;
    }
    final id = 'ride_$requestId';
    final code = _bookingCurrency(body);
    final bookedStops = <Map<String, dynamic>>[
      if (body['stops'] is List)
        for (final raw in body['stops'] as List)
          if (raw is Map && raw['lat'] is num && raw['lng'] is num)
            {
              'address': raw['address']?.toString() ?? '',
              'lat': raw['lat'],
              'lng': raw['lng'],
            },
    ];
    return _withPlaces({
      'id': id,
      'tripId': id,
      // Legacy read-only alias of tripId during migration.
      'rideId': id,
      // rider-r4-5: the openapi TripProjection required fields the legacy
      // keys below do not cover. One stand-in rider; the pickup's zone.
      'riderId': mockRiderId,
      'zoneId': _zoneOf(body).id,
      'pinRequired': false,
      'kind': scheduled ? TripKind.scheduled.wireName : TripKind.live.wireName,
      'status': tripStatus.wireName,
      'ratingStatus': TripRatingStatus.notRequested.wireName,
      'version': 1,
      'sequence': 1,
      'eventId': 'ev_${id}_1',
      'eventKind': 'trip_projection',
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
      // Contract v0.4.0: null until a driver accepts.
      'acceptedAt': null,
      if (body['scheduledAt'] == null)
        'searchStartedAt': DateTime.now().toUtc().toIso8601String(),
      'categoryId': categoryId,
      'paymentMethodId': paymentMethodId,
      // Transitional aliases keep older read-side tests compatible while every
      // new write uses the canonical backend vocabulary above.
      'rideType': categoryId,
      // openapi PaymentMethod: the method kind; the id is paymentMethodId.
      'paymentMethod': _paymentMethodKind(paymentMethodId),
      // Contract v0.3.0: Money on the wire, no whole-unit doubles, in the
      // currency of the pickup's zone (Q7). The flat `currency` sits next to
      // the flat minor fields for older readers.
      'currency': code,
      if (_bookingFareMinor(body, code) case final minor?) ...{
        'fare': _money(minor, code),
        'bookedFare': _money(minor, code),
        // ARCH-20 / contract C-4: the server owns the offer ceiling.
        'maxOfferMinor': _maxOfferMinorFor(minor, code),
      },
      // rider-9 / owner decision 5: the booked route goes through the
      // booked stops, as the booking quote priced it.
      'bookedKm': _routedKm(body),
      'stops': bookedStops,
      'bookedStops': [...bookedStops],
      'quoteId': body['quoteId'],
      'quoteSignedPayload': body['quoteSignedPayload'],
      'quoteExpiresAt': body['quoteExpiresAt'],
      'quoteTotalMinor': body['quoteTotalMinor'],
      'useWalletFirst': body['useWalletFirst'] == true,
      'walletAmountMinor': (body['walletAmountMinor'] as num?)?.round() ?? 0,
      'pickupAddress': body['pickupAddress'],
      'destinationAddress': body['destinationAddress'],
      'pickupLat': body['pickupLat'],
      'pickupLng': body['pickupLng'],
      'destinationLat': body['destinationLat'],
      'destinationLng': body['destinationLng'],
      'scheduledAt': body['scheduledAt'],
      // Rider notes are part of the ride the driver is given, so the stand-in
      // backend stores them the way the real one will.
      'notes': body['notes'],
    });
  }

  /// The stand-in's one rider (`TripProjection.riderId`).
  static const mockRiderId = 'rdr_mock';

  /// rider-r4-5: `pickup` / `dropoff` as openapi `Place`s, from the flat
  /// legacy fields every write here still updates. Called again after each
  /// change of those fields so the two shapes never disagree.
  static Map<String, dynamic> _withPlaces(Map<String, dynamic> ride) {
    for (final (place, flat) in const [
      ('pickup', 'pickup'),
      ('dropoff', 'destination'),
    ]) {
      final lat = ride['${flat}Lat'];
      final lng = ride['${flat}Lng'];
      if (lat is num && lng is num) {
        ride[place] = {
          'address': ride['${flat}Address']?.toString() ?? '',
          'lat': lat,
          'lng': lng,
        };
      }
    }
    return ride;
  }

  /// openapi `PaymentMethod` for a client method id (`card_…` and `cards`
  /// are saved cards; `apple` / `google` are the v0.3 aliases).
  static String _paymentMethodKind(String id) {
    final value = id.trim().toLowerCase();
    if (value == 'apple' || value == 'apple_pay') return 'apple_pay';
    if (value == 'google' || value == 'google_pay') return 'google_pay';
    if (value == 'cash' || value == 'wallet') return value;
    return 'card';
  }

  List<Map<String, dynamic>> _nearby(Map<String, dynamic>? ride) {
    final lat = (ride?['pickupLat'] as num?)?.toDouble();
    final lng = (ride?['pickupLng'] as num?)?.toDouble();
    if (lat == null || lng == null) return const [];
    return [
      {'id': 'veh_a', 'lat': lat + 0.0021, 'lng': lng - 0.0014, 'bearing': 42},
      {'id': 'veh_b', 'lat': lat - 0.0016, 'lng': lng + 0.0022, 'bearing': 210},
      {'id': 'veh_c', 'lat': lat + 0.0008, 'lng': lng + 0.0018, 'bearing': 128},
    ];
  }

  http.StreamedResponse _json(
    int status,
    Map<String, dynamic> body,
    String requestId,
  ) {
    final bytes = utf8.encode(jsonEncode(body));
    return http.StreamedResponse(
      Stream<List<int>>.value(bytes),
      status,
      headers: {
        'content-type': 'application/json',
        'x-request-id': requestId,
      },
      contentLength: bytes.length,
    );
  }

  /// The booked fare in [code]: `fare: Money`, else the pre-v0.3
  /// whole-unit `price`, else the quote total.
  static int? _bookingFareMinor(Map<String, dynamic> body, String code) {
    final fare = body['fare'];
    if (fare is Map && fare['amountMinor'] is int) {
      return fare['amountMinor'] as int;
    }
    final price = body['price'];
    if (price is num) return Money.fromLegacyMajor(price, code).amountMinor;
    final quoted = body['quoteTotalMinor'];
    return quoted is int ? quoted : null;
  }

  /// Q7: a booking's currency is its quote's (the pickup's zone), else the
  /// confirmed fare's, else the zone of its pickup.
  String _bookingCurrency(Map<String, dynamic> body) {
    final quote = quotes[body['quoteId']];
    final fare = body['fare'];
    return Money.normalizeCurrency(quote?['currency']) ??
        Money.normalizeCurrency(fare is Map ? fare['currency'] : null) ??
        _zoneOf(body).currency;
  }
}

/// One remembered answer to an idempotent request (RC-12).
class IdempotentReplay {
  const IdempotentReplay({
    required this.body,
    required this.response,
    required this.at,
  });

  /// The request body it answered, encoded.
  final String body;

  /// The answer, encoded when it was given.
  final String response;
  final DateTime at;
}
