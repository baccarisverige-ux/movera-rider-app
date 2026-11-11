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
import 'package:movera_rider/core/contracts/raise_limit.dart';
import 'package:movera_rider/core/contracts/ride_status.dart';
import 'package:movera_rider/core/contracts/trip_settlement.dart';
import 'package:movera_rider/core/contracts/trip_status.dart';
import 'package:movera_rider/core/contracts/trip_transitions.dart';
import 'package:movera_rider/core/contracts/wire_time.dart';
import 'package:movera_rider/core/logging/app_log.dart';
import 'package:movera_rider/core/maps/geo_distance.dart';
import 'package:movera_rider/core/storage/preferences_store.dart';

part 'in_process_mock_client_catalog.dart';
part 'in_process_mock_client_pricing.dart';
part 'in_process_mock_client_trips.dart';

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

  /// rider-u13: the pickup each trip had when its driver accepted, which
  /// every later Q40 move is measured from (not the pickup as it stands
  /// after earlier moves). Set on the first move after accept; cleared when
  /// the trip is back in dispatch. Server-side only; not in the projection.
  final Map<String, ({double lat, double lng})> _acceptedPickup = {};

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
  final List<Map<String, dynamic>> rideTypes = _seedRideTypes();

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
    // The map's nearby cars are asked every few seconds and change nothing:
    // no need to write the rides to storage for them.
    if (persistRides && request.url.path != '/api/v1/rider/nearby-vehicles') {
      await _restoreRidesOnce();
      final response = await _handle(request);
      await _persistRides();
      return response;
    }
    return _handle(request);
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

    if (path == '/api/v1/rider/nearby-vehicles' && method == 'GET') {
      final lat = double.tryParse(request.url.queryParameters['lat'] ?? '');
      final lng = double.tryParse(request.url.queryParameters['lng'] ?? '');
      if (lat == null || lng == null || lat.abs() > 90 || lng.abs() > 180) {
        return _json(
          400,
          _error('invalid_request', requestId, reason: 'invalid_point'),
          requestId,
        );
      }
      return _json(200, {
        'items': demoNearbyCars(lat, lng, _clock()),
        'refreshSeconds': 5,
        'radiusMeters': 3000,
      }, requestId);
    }
    if (path == '/api/v1/locations/reverse-geocode' && method == 'POST') {
      final latitude = body['latitude'];
      final longitude = body['longitude'];
      if (latitude is! num || longitude is! num) {
        status = 400;
        payload = _error(
          'invalid_request',
          requestId,
          reason: 'invalid_coordinates',
        );
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
        final longitude =
            18.0686 + ((((hash ~/ 1201) % 1601) - 800) / 100000.0);
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
        final expiresAt = DateTime.now().toUtc().add(
          const Duration(minutes: 5),
        );
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
        payload = _error(
          'invalid_request',
          requestId,
          reason: 'invalid_otp_session',
        );
      } else {
        final expiresAt = DateTime.tryParse('${session['expiresAt'] ?? ''}');
        if (expiresAt == null || !expiresAt.isAfter(DateTime.now().toUtc())) {
          status = 410;
          payload = _error('invalid_request', requestId, reason: 'otp_expired');
        } else if (session['code'] != code.trim()) {
          status = 400;
          payload = _error(
            'invalid_request',
            requestId,
            reason: 'invalid_otp_code',
          );
        } else {
          otpSessions.remove(sessionId);
          final normalizedPhone = phone.trim();
          final isNewRider = knownPhones.add(normalizedPhone);
          final linkToken = session['linkToken'];
          final provider = linkToken is String
              ? pendingLinks.remove(linkToken)
              : null;
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
      final idToken = body['idToken'];
      if (provider is! String ||
          provider.trim().isEmpty ||
          // Contract §8 ProviderSignInRequest: provider, idToken and app.
          idToken is! String ||
          idToken.isEmpty ||
          (body['app'] != 'rider' && body['app'] != 'driver')) {
        status = 400;
        payload = _error(
          'invalid_request',
          requestId,
          reason: 'invalid_provider',
        );
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
      if (refreshToken is! String ||
          !refreshToken.startsWith('mock-refresh-')) {
        status = 401;
        payload = _error(
          'unauthenticated',
          requestId,
          reason: 'invalid_refresh',
        );
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
        payload = _error(
          'invalid_request',
          requestId,
          reason: 'invalid_push_device',
        );
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
    } else if (path == '/api/v1/push/devices/unregister' && method == 'POST') {
      final token = body['token'];
      if (token is! String || token.trim().isEmpty) {
        status = 400;
        payload = _error(
          'invalid_request',
          requestId,
          reason: 'invalid_push_device',
        );
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
      final fresh =
          age != null && !age.isNegative && age <= const Duration(minutes: 5);
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
      final fromMap = from is Map
          ? Map<String, dynamic>.from(from)
          : const <String, dynamic>{};
      final toMap = to is Map
          ? Map<String, dynamic>.from(to)
          : const <String, dynamic>{};
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
          validation == 'wallet_amount_invalid'
              ? 'invalid_request'
              : 'conflict',
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
          (rating != null &&
              (rating is! num ||
                  rating < 1 ||
                  rating > 5 ||
                  rating != rating.roundToDouble())) ||
          (tipMinor != null &&
              (tipMinor is! int ||
                  tipMinor <= 0 ||
                  tipMinor > 999900 ||
                  body['currency'] != _currencyOf(ride)))) {
        status = 400;
        payload = _error(
          'invalid_request',
          requestId,
          reason: 'invalid_feedback',
        );
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
        payload = _error(
          'invalid_request',
          requestId,
          reason: 'invalid_dispute',
        );
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
          final reason =
              body['reason'] ??
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
          if (body['lat'] != null &&
              body['command'] == null &&
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
          final moved =
              body['pickupAddress'] != null &&
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
          final method = (methodId ?? body['paymentMethod'] ?? '').toString();
          final cash = methodId != null
              ? methodId == 'cash'
              : method.toLowerCase() == 'cash' ||
                    method.toLowerCase().contains('pay in car');
          final difference = pricing['differenceMinor'] as int;
          // rider-u43: any difference (cents and millimes count).
          if (!cash && difference != 0) {
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
        final searching =
            current == TripStatus.requested ||
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
          // rider-8: a raise or a searching edit is a committed change like
          // any other: new version, updatedAt and event.
          final edited =
              (increase != null && fare != null) ||
              const [
                'pickupAddress',
                'pickupLat',
                'pickupLng',
                'destinationAddress',
                'destinationLat',
                'destinationLng',
              ].any((key) => body[key] != null);
          if (edited) _touch(ride);
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
      payload = {'code': 'OK', 'profile': riderProfile, 'requestId': requestId};
    } else if (path == '/api/v1/rider/profile' && method == 'PATCH') {
      // FLOW-7 / C-12 (PROPOSED): name, language and consents. A field left
      // out keeps the value the server holds (rider-u148).
      // The contract's RiderProfileUpdate says firstName; older callers name.
      final name = body['firstName'] ?? body['name'];
      final consents = body['consents'];
      if ((name != null && (name is! String || name.trim().length > 80)) ||
          (consents != null && consents is! Map)) {
        status = 422;
        payload = _error(
          'invalid_request',
          requestId,
          reason: 'invalid_profile',
        );
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
          {'id': 'cash', 'kind': 'cash', 'label': 'Cash'},
        ],
        'defaultMethodId': defaultPaymentMethodId,
        'requestId': requestId,
      };
    } else if (path == '/api/v1/payment-methods/default' && method == 'PATCH') {
      final methodId = body['methodId'];
      if (methodId is! String || methodId.trim().isEmpty) {
        status = 422;
        payload = _error(
          'invalid_request',
          requestId,
          reason: 'invalid_payment_method',
        );
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

  /// The stand-in's one rider (`TripProjection.riderId`).
  static const mockRiderId = 'rdr_mock';

  /// Demo cars for `GET /rider/nearby-vehicles` (contract v0.5.2 §13): seven
  /// cars driving back and forth on straight streets around the point, so
  /// the map moves like a real city. Same keys all along, rounded positions.
  static List<Map<String, dynamic>> demoNearbyCars(
    double lat,
    double lng,
    DateTime now,
  ) {
    const count = 7;
    final seconds = now.millisecondsSinceEpoch / 1000;
    final cosLat = math.max(0.2, math.cos(lat * math.pi / 180));
    final cars = <Map<String, dynamic>>[];
    for (var i = 0; i < count; i++) {
      // Where the car's street is and which way it runs.
      final around = i * 2 * math.pi / count + 0.4;
      final distance = 260.0 + 170.0 * i;
      final streetLat = lat + distance * math.cos(around) / 111320;
      final streetLng = lng + distance * math.sin(around) / (111320 * cosLat);
      final street = (i * 47 + 20) % 180 * math.pi / 180;
      // About 8 m/s, turning back at each end of a 500 m stretch.
      const half = 250.0;
      final phase = seconds * 8 / half + i * 1.7;
      final along = half * math.sin(phase);
      final forward = math.cos(phase) >= 0;
      final carLat = streetLat + along * math.cos(street) / 111320;
      final carLng = streetLng + along * math.sin(street) / (111320 * cosLat);
      final heading = (street * 180 / math.pi + (forward ? 0 : 180)) % 360;
      cars.add({
        'key': 'demo-car-$i',
        'lat': double.parse(carLat.toStringAsFixed(4)),
        'lng': double.parse(carLng.toStringAsFixed(4)),
        'heading': heading.roundToDouble(),
      });
    }
    return cars;
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
