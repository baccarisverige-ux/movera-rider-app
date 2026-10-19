import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:movera_rider/core/api/safety_mock_api.dart';
import 'package:movera_rider/core/utils/request_id.dart';
import 'package:movera_rider/core/api/mock_catalog_fares.dart';
import 'package:movera_rider/core/contracts/category_ids.dart';
import 'package:movera_rider/core/contracts/ride_status.dart';
import 'package:movera_rider/core/contracts/trip_settlement.dart';
import 'package:movera_rider/core/contracts/trip_status.dart';
import 'package:movera_rider/core/contracts/trip_transitions.dart';
import 'package:movera_rider/core/contracts/wire_time.dart';

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
  });

  final Duration latency;

  /// FLOW-9: keep the Safety mock's state across launches (the app's own
  /// demo transport). Off for tests that build a mock of their own.
  final bool persistSafety;

  /// ARCH-3: like a real backend, the mock ends a search nobody accepted.
  /// A ride still searching this long after it was created reads back as
  /// `noDriverFound`, so the demo still ends when no driver is assigned.
  final Duration searchExpiresAfter;
  final Map<String, Map<String, dynamic>> idempotency = {};
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
      'price': price,
      'currency': currency,
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
      return _json(500, {
        'code': 'SERVER_ERROR',
        'message': 'Mock 500',
        'requestId': requestId,
      }, requestId);
    }

    if (key != null && key.isNotEmpty && idempotency.containsKey(key)) {
      return _json(200, idempotency[key]!, requestId);
    }

    late Map<String, dynamic> payload;
    var status = 200;
    final parts = path.split('/');

    if (path == '/api/v1/locations/reverse-geocode' && method == 'POST') {
      final latitude = body['latitude'];
      final longitude = body['longitude'];
      if (latitude is! num || longitude is! num) {
        status = 400;
        payload = {'code': 'INVALID_COORDINATES', 'requestId': requestId};
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
        payload = {'code': 'INVALID_QUERY', 'requestId': requestId};
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
        payload = {'code': 'INVALID_PHONE', 'requestId': requestId};
      } else if (linkToken != null &&
          (linkToken is! String || !pendingLinks.containsKey(linkToken))) {
        status = 400;
        payload = {'code': 'INVALID_LINK', 'requestId': requestId};
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
        payload = {'code': 'INVALID_OTP_SESSION', 'requestId': requestId};
      } else {
        final expiresAt = DateTime.tryParse('${session['expiresAt'] ?? ''}');
        if (expiresAt == null || !expiresAt.isAfter(DateTime.now().toUtc())) {
          status = 410;
          payload = {'code': 'OTP_EXPIRED', 'requestId': requestId};
        } else if (session['code'] != code.trim()) {
          status = 401;
          payload = {'code': 'INVALID_OTP', 'requestId': requestId};
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
        payload = {'code': 'INVALID_PROVIDER', 'requestId': requestId};
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
        payload = {'code': 'INVALID_REFRESH', 'requestId': requestId};
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
        payload = {'code': 'INVALID_PUSH_DEVICE', 'requestId': requestId};
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
        payload = {'code': 'INVALID_PUSH_DEVICE', 'requestId': requestId};
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
        payload = {
          'code': 'REAUTH_REQUIRED',
          'message': 'Fresh reauthentication is required.',
          'requestId': requestId,
        };
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
        payload = {
          'code': validation,
          'message': 'Booking quote is missing, expired or does not match.',
          'requestId': requestId,
        };
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
        payload = {'code': 'NOT_FOUND', 'requestId': requestId};
      } else if (_statusOf(ride) != TripStatus.completed) {
        status = 409;
        payload = {'code': 'RIDE_NOT_COMPLETE', 'requestId': requestId};
      } else if ((rating == null && tipMinor == null) ||
          (rating != null && (rating is! num || rating < 1 || rating > 5 || rating * 2 != (rating * 2).round())) ||
          (tipMinor != null && (tipMinor is! int || tipMinor <= 0 || tipMinor > 999900 || body['currency'] != 'SEK'))) {
        status = 400;
        payload = {'code': 'INVALID_FEEDBACK', 'requestId': requestId};
      } else {
        ride['feedback'] = {
          if (rating != null) 'rating': rating,
          if (tipMinor != null) 'tipMinor': tipMinor,
          if (tipMinor != null) 'currency': 'SEK',
        };
        if (rating != null) {
          // ratingTransitions: (not_requested →) pending → submitted.
          ride['ratingStatus'] = TripRatingStatus.submitted.wireName;
          _touch(ride);
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
        payload = {'code': 'INVALID_DISPUTE', 'requestId': requestId};
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
    } else if (parts.length >= 6 &&
        parts[1] == 'api' &&
        parts[3] == 'rides' &&
        (parts.last == 'cancel' || parts.last == 'end-early') &&
        method == 'POST') {
      final id = parts[4];
      final ride = rides[id];
      if (ride == null) {
        status = 404;
        payload = {'code': 'NOT_FOUND', 'requestId': requestId};
      } else if (_statusOf(ride) == TripStatus.cancelledByRider) {
        // Cancel-first: the rider's optional reason arrives after the cancel.
        final reason = body['reasonCode'] ?? body['reason'];
        if (reason is String && ride['cancellationReason'] == null) {
          ride['cancellationReason'] = reason;
          (ride['cancellation'] as Map?)?['reasonCode'] = reason;
        }
        payload = {'code': 'OK', 'ride': ride, 'requestId': requestId};
      } else {
        // `cancel` before boarding, `end_early` once the rider is on board
        // (POST .../end-early); anything else is invalid_transition.
        final command = parts.last == 'end-early' ? 'end_early' : 'cancel';
        if (!_apply(ride, command, TripActor.rider)) {
          status = 409;
          payload = _invalidTransition(ride, command, requestId);
        } else {
          final reason = body['reasonCode'] ?? body['reason'];
          if (reason is String) ride['cancellationReason'] = reason;
          ride['cancellation'] = {
            'actor': TripActor.rider.wireName,
            'reasonCode': reason is String ? reason : null,
            'at': ride['updatedAt'],
            'fee': null,
          };
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
      if (ride == null) {
        status = 404;
        payload = {'code': 'NOT_FOUND', 'requestId': requestId};
      } else {
        final denied = _simulate(ride, body);
        if (denied != null) {
          status = 409;
          payload = _invalidTransition(ride, denied, requestId);
        } else {
          if (body['driver'] is Map) ride['driver'] = body['driver'];
          if (body['lat'] != null) ride['driverLat'] = body['lat'];
          if (body['lng'] != null) ride['driverLng'] = body['lng'];
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
        payload = {'code': 'NOT_FOUND', 'requestId': requestId};
      } else {
        final denied = _routeChangeDenied(ride, body);
        if (denied != null) {
          status = 409;
          payload = {'code': denied, 'ride': ride, 'requestId': requestId};
        } else {
          final pricing = _routeChangePricing(ride, body);
          final quoteId = 'rq_${newRequestId()}';
          final expiresAt = DateTime.now()
              .add(const Duration(minutes: 5))
              .toUtc()
              .toIso8601String();
          final newTotalMinor =
              ((pricing['newPriceKr'] as double) * 100).round();
          final differenceMinor =
              ((pricing['differenceKr'] as double) * 100).round();
          routeQuotes[quoteId] = {
            'rideId': parts[4],
            'route': _routeFingerprint(body),
            'expiresAt': expiresAt,
            'newTotalMinor': newTotalMinor,
          };
          payload = {
            'code': 'OK',
            ...pricing,
            'routeQuoteId': quoteId,
            'expiresAt': expiresAt,
            'newTotalMinor': newTotalMinor,
            'differenceMinor': differenceMinor,
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
        payload = {'code': 'NOT_FOUND', 'requestId': requestId};
      } else if (routeChange) {
        final denied =
            _routeChangeDenied(ride, body) ?? _routeQuoteDenied(id, ride, body);
        if (denied != null) {
          status = 409;
          payload = {'code': denied, 'ride': ride, 'requestId': requestId};
        } else {
          final pricing = _routeChangePricing(ride, body);
          if (body['pickupAddress'] != null) {
            ride['pickupAddress'] = body['pickupAddress'];
            ride['pickupLat'] = body['pickupLat'];
            ride['pickupLng'] = body['pickupLng'];
          }
          ride['destinationAddress'] = body['destinationAddress'];
          ride['destinationLat'] = body['destinationLat'];
          ride['destinationLng'] = body['destinationLng'];
          ride['stops'] = pricing['stops'];
          ride['price'] = pricing['newPriceKr'];
          ride['maxOfferMinor'] = _maxOfferMinor(pricing['newPriceKr'] as num);
          ride['version'] = ((ride['version'] as num?)?.toInt() ?? 0) + 1;
          ride['updatedAt'] = DateTime.now().toUtc().toIso8601String();
          // The driver app is told on its next poll; the log is what admin
          // reads later.
          ride['driverNotifiedAt'] = ride['updatedAt'];
          // Pay in car only shows the new price; any other method is
          // charged or refunded the difference right away.
          // ARCH-9: the method id decides; the label is the old contract.
          final methodId = body['paymentMethodId']?.toString();
          final method =
              (methodId ?? body['paymentMethod'] ?? '').toString();
          final cash = methodId != null
              ? methodId == 'cash'
              : method.toLowerCase() == 'cash' ||
                    method.toLowerCase().contains('pay in car');
          final difference = pricing['differenceKr'] as double;
          if (!cash && difference.abs() >= 0.5) {
            (ride['paymentAdjustments'] ??= <Map<String, dynamic>>[]).add({
              'at': ride['updatedAt'],
              'method': method,
              'amountKr': difference,
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
            'newPriceKr': pricing['newPriceKr'],
            'differenceKr': pricing['differenceKr'],
          });
          payload = {
            'code': 'OK',
            'ride': ride,
            ...pricing,
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
          payload = {
            'code': 'RIDE_NOT_SEARCHING',
            'message': 'Ride can only be edited while searching',
            'ride': ride,
            'requestId': requestId,
          };
        } else if (body.containsKey('offerIncreaseKr') &&
            !_validOfferIncrease(body['offerIncreaseKr'], ride['price'])) {
          status = 422;
          payload = {
            'code': 'INVALID_OFFER',
            'message': 'Offer increase must be a positive whole amount',
            'requestId': requestId,
          };
        } else if (_offerAboveMaximum(ride, body['offerIncreaseKr'])) {
          // ARCH-20: the ceiling holds on the server, whatever the client
          // computed after a reload.
          status = 409;
          payload = {
            'code': 'OFFER_ABOVE_MAXIMUM',
            'message': 'Offer is above the maximum for this ride',
            'ride': ride,
            'requestId': requestId,
          };
        } else {
          // D-012: the server prices an offer bump itself from the rider's
          // intent (offerIncreaseKr). A client-sent `price` is never treated
          // as authority and is ignored. The ceiling is checked above.
          final increase = body['offerIncreaseKr'];
          if (increase is num) {
            ride['price'] = (ride['price'] as num) + increase;
            ride['offerIncreaseKr'] = increase;
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
        payload = {'code': 'NOT_FOUND', 'requestId': requestId};
      } else {
        _expireSearchIfDue(ride);
        payload = {'code': 'OK', 'ride': ride, 'requestId': requestId};
      }
    } else if (path == '/api/v1/payments' && method == 'POST') {
      final amountMinor = body['amountMinor'];
      final currency = body['currency'];
      if (amountMinor is! int ||
          amountMinor <= 0 ||
          currency is! String ||
          currency.trim().toUpperCase() != 'SEK') {
        status = 400;
        payload = {
          'code': 'INVALID_PAYMENT_INTENT',
          'requestId': requestId,
        };
      } else {
        final intent = <String, dynamic>{
          'id': 'pi_$requestId',
          'status': 'requires_confirmation',
          'amountMinor': amountMinor,
          'currency': 'SEK',
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
        payload = {'code': 'PAYMENT_NOT_FOUND', 'requestId': requestId};
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
        payload = {'code': 'PAYMENT_NOT_FOUND', 'requestId': requestId};
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
    } else if (path == '/api/v1/rider/profile' && method == 'PATCH') {
      // FLOW-7 / C-12 (PROPOSED): name, language and consents.
      final name = body['name'];
      final consents = body['consents'];
      if (name is! String ||
          name.trim().length > 80 ||
          (consents != null && consents is! Map)) {
        status = 422;
        payload = {'code': 'INVALID_PROFILE', 'requestId': requestId};
      } else {
        riderProfile = {
          'name': name.trim(),
          if (body['language'] is String) 'language': body['language'],
          'consents': {
            ...?(riderProfile?['consents'] as Map?),
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
          {'id': 'cash', 'kind': 'cash', 'label': 'Pay in car'},
        ],
        'defaultMethodId': defaultPaymentMethodId,
        'requestId': requestId,
      };
    } else if (path == '/api/v1/payment-methods/default' &&
        method == 'PATCH') {
      final methodId = body['methodId'];
      if (methodId is! String || methodId.trim().isEmpty) {
        status = 422;
        payload = {'code': 'INVALID_PAYMENT_METHOD', 'requestId': requestId};
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
        payload = {'code': 'NOT_FOUND', 'path': path, 'requestId': requestId};
      }
    }

    if (key != null && key.isNotEmpty && status < 400) {
      idempotency[key] = payload;
    }
    return _json(status, payload, requestId);
  }

  /// Demo-only places around Södertälje and Stockholm, so address search can
  /// be tried on GitHub Pages. The live API searches real addresses.
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

  /// One committed change: version + 1, new updatedAt.
  static void _touch(Map<String, dynamic> ride) {
    ride['version'] = ((ride['version'] as num?)?.toInt() ?? 0) + 1;
    ride['updatedAt'] = DateTime.now().toUtc().toIso8601String();
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
        'reasonCode': null,
        'at': DateTime.now().toUtc().toIso8601String(),
        'fee': null,
      };
    }
    _touch(ride);
    return true;
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
          _touch(ride);
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
          _touch(ride);
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

  /// Pickup can move until the driver is at the door; the destination and
  /// the stops can change until the trip is over.
  String? _routeChangeDenied(
    Map<String, dynamic> ride,
    Map<String, dynamic> body,
  ) {
    final current = _statusOf(ride);
    if (current.isTerminal) return 'RIDE_FINISHED';
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
      return 'PICKUP_LOCKED';
    }
    if (body['destinationLat'] is! num || body['destinationLng'] is! num) {
      return 'DESTINATION_REQUIRED';
    }
    return null;
  }

  /// ARCH-20: true when [increase] would take the fare over the ceiling.
  static bool _offerAboveMaximum(Map<String, dynamic> ride, Object? increase) {
    final max = ride['maxOfferMinor'];
    final price = ride['price'];
    if (increase is! num || max is! num || price is! num) return false;
    return ((price + increase) * 100).round() > max;
  }

  /// The highest fare a rider may offer for a ride priced [priceKr]: 1.8×.
  static int _maxOfferMinor(num priceKr) =>
      ((priceKr * 1.8).roundToDouble() * 100).round();

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
      return 'ROUTE_QUOTE_NOT_FOUND';
    }
    final expiresAt = DateTime.tryParse(quote['expiresAt'] as String? ?? '');
    if (expiresAt == null || !expiresAt.isAfter(DateTime.now())) {
      return 'ROUTE_QUOTE_EXPIRED';
    }
    if (quote['route'] != _routeFingerprint(body)) {
      return 'ROUTE_QUOTE_MISMATCH';
    }
    final quoted = quote['newTotalMinor'] as int;
    final expected = (body['expectedTotalMinor'] as num?)?.round();
    final now =
        ((_routeChangePricing(ride, body)['newPriceKr'] as double) * 100)
            .round();
    if ((expected != null && expected != quoted) || now != quoted) {
      return 'ROUTE_QUOTE_PRICE_CHANGED';
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

  /// New price for a changed route: the booked price, plus 25 kr per stop
  /// and 12 kr per extra kilometre beyond what was booked. Shorter routes
  /// get the difference back.
  Map<String, dynamic> _routeChangePricing(
    Map<String, dynamic> ride,
    Map<String, dynamic> body,
  ) {
    final bookedPrice =
        (ride['bookedPrice'] as num?)?.toDouble() ??
        (ride['price'] as num?)?.toDouble() ??
        0;
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
    double routeKm = 0;
    if (pLat != null && pLng != null) {
      var lat = pLat;
      var lng = pLng;
      for (final stop in stops) {
        routeKm += _km(lat, lng, stop['lat'] as num, stop['lng'] as num);
        lat = stop['lat'] as num;
        lng = stop['lng'] as num;
      }
      routeKm += _km(lat, lng, dLat, dLng);
    }
    final bookedKm = (ride['bookedKm'] as num?)?.toDouble() ?? routeKm;
    final newPrice =
        (bookedPrice + stops.length * 25 + (routeKm - bookedKm) * 12)
            .clamp(bookedPrice * 0.5, double.infinity)
            .roundToDouble();
    final current = (ride['price'] as num?)?.toDouble() ?? bookedPrice;
    return {
      'newPriceKr': newPrice,
      'differenceKr': newPrice - current,
      'routeKm': double.parse(routeKm.toStringAsFixed(2)),
      'stops': stops,
    };
  }

  /// The catalog price covers a trip this long; the fare then moves 12 kr
  /// per kilometre either way (the route-change rate), never below 60% of
  /// the catalog price. So a 3 km quote is the demo list price.
  static const _catalogTripMeters = 3000;
  static const _krPerKm = 12;

  int _fareKr(String rideType, int distanceMeters) {
    final catalogKr = _catalogPriceKr(rideType);
    final extraKm = (distanceMeters - _catalogTripMeters) / 1000;
    final kr = (catalogKr + extraKm * _krPerKm).round();
    return math.max((catalogKr * 0.6).round(), kr);
  }

  /// Pickup → stops → destination in metres, or null without the points.
  int? _routedMeters(Map<String, dynamic> body) {
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
    return math.max(1, (km * 1000).round());
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
    final catalogMinor = _catalogPriceKr(rideType) * 100;
    final fullMinor = _fareKr(rideType, distanceMeters) * 100;
    // Demo promotion: discounts the ride types it names, capped per ride.
    final promo = activePromotion;
    final eligible =
        promo != null &&
        (promo['rideTypes'] as List? ?? const []).contains(rideType);
    final discountMinor = eligible
        ? ((fullMinor * (promo['percentOff'] as num) / 100).round()).clamp(
            0,
            (promo['maxDiscountMinor'] as num?)?.round() ?? fullMinor,
          )
        : 0;
    final minor = fullMinor - discountMinor;
    final id = 'q_${rideType}_${newRequestId()}';
    return {
      'id': id,
      'quoteId': id,
      'rideType': rideType,
      'totalMinor': minor,
      'amountMinor': minor,
      'currency': currency,
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
      return 'QUOTE_REQUIRED';
    }

    final quote = quotes[quoteId];
    if (quote == null) return 'QUOTE_NOT_FOUND';
    if (quote['signedPayload'] != signed) return 'QUOTE_SIGNATURE_MISMATCH';

    final expiresAt = DateTime.tryParse(expiryRaw);
    final serverExpiry = DateTime.tryParse(quote['expiresAt'] as String? ?? '');
    if (expiresAt == null ||
        serverExpiry == null ||
        expiresAt.toUtc() != serverExpiry.toUtc() ||
        !serverExpiry.isAfter(DateTime.now())) {
      return 'QUOTE_EXPIRED';
    }

    final serverTotal = (quote['totalMinor'] as num?)?.round();
    if (serverTotal == null || serverTotal != quotedTotal) {
      return 'QUOTE_AMOUNT_MISMATCH';
    }

    final categoryId = CategoryIds.canonical((body['categoryId'] ?? '').toString());
    if (quote['rideType'] != categoryId) return 'QUOTE_CATEGORY_MISMATCH';

    final submittedPrice = (body['price'] as num?)?.toDouble();
    if (submittedPrice == null ||
        (submittedPrice * 100).round() != serverTotal) {
      return 'QUOTE_PRICE_MISMATCH';
    }

    // "Use wallet balance first" (contract C-3): the wallet part may not
    // exceed the fare, and is zero when the rider switched it off.
    final walletMinor = (body['walletAmountMinor'] as num?)?.round() ?? 0;
    final walletFirst = body['useWalletFirst'] == true;
    if (walletMinor < 0 ||
        walletMinor > serverTotal ||
        (!walletFirst && walletMinor != 0)) {
      return 'WALLET_AMOUNT_INVALID';
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
    return {
      'id': id,
      'tripId': id,
      // Legacy read-only alias of tripId during migration.
      'rideId': id,
      'kind': scheduled ? TripKind.scheduled.wireName : TripKind.live.wireName,
      'status': tripStatus.wireName,
      'ratingStatus': TripRatingStatus.notRequested.wireName,
      'version': 1,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
      if (body['scheduledAt'] == null)
        'searchStartedAt': DateTime.now().toUtc().toIso8601String(),
      'categoryId': categoryId,
      'paymentMethodId': paymentMethodId,
      // Transitional aliases keep older read-side tests compatible while every
      // new write uses the canonical backend vocabulary above.
      'rideType': categoryId,
      'paymentMethod': paymentMethodId,
      'price': body['price'],
      'bookedPrice': body['price'],
      // ARCH-20 / contract C-4: the server owns the offer ceiling.
      if (body['price'] is num) 'maxOfferMinor': _maxOfferMinor(body['price']),
      'bookedKm':
          body['pickupLat'] is num &&
              body['pickupLng'] is num &&
              body['destinationLat'] is num &&
              body['destinationLng'] is num
          ? _km(
              body['pickupLat'] as num,
              body['pickupLng'] as num,
              body['destinationLat'] as num,
              body['destinationLng'] as num,
            )
          : null,
      'stops': <Map<String, dynamic>>[
        if (body['stops'] is List)
          for (final raw in body['stops'] as List)
            if (raw is Map && raw['lat'] is num && raw['lng'] is num)
              {
                'address': raw['address']?.toString() ?? '',
                'lat': raw['lat'],
                'lng': raw['lng'],
              },
      ],
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
    };
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

  static bool _validOfferIncrease(Object? increase, Object? currentPrice) =>
      increase is num &&
      increase > 0 &&
      increase == increase.roundToDouble() &&
      currentPrice is num;
}
