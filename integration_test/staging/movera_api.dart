import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

/// A small HTTP client for the staging API, used by the device tests to
/// play the OTHER side of a trip (the rider while the driver app is on the
/// phone; the driver while the rider app is on it).
///
/// App-agnostic on purpose (no app package import). Shared with the driver
/// app's suite (Movera-driver-app integration_test/staging/movera_api.dart,
/// merged #570): everything above [DriverApi] is that file unchanged; the
/// rider suite adds [DriverApi] at the end (G31 rider, owner 2026-11-12).
/// Copy the whole file back to the driver repo when it changes, so both
/// repos keep the same file.
///
/// Never logs anything. Bodies, tokens, phone numbers and codes stay in
/// memory; callers print only statuses, reasons and ids.

/// One answer: status (0 = no answer / timeout) and the decoded body.
class ApiAnswer {
  const ApiAnswer(this.status, this.body, {this.error});

  final int status;
  final Object? body;

  /// The exception type when the call threw (never its message).
  final String? error;

  bool get ok => status >= 200 && status < 300;

  Map<String, dynamic>? get map =>
      body is Map ? Map<String, dynamic>.from(body! as Map) : null;

  /// `reason` (else `code`) of an error answer; safe to print.
  String? get reason {
    final m = map;
    if (m == null) return null;
    final r = m['reason'] ?? m['code'];
    return r is String ? r : null;
  }

  /// "201", "409 invalid_transition", "0 TimeoutException": safe to print.
  String get short =>
      '$status${reason == null ? '' : ' $reason'}${error == null ? '' : ' $error'}';
}

class MoveraApi {
  MoveraApi(
    this.base, {
    http.Client? client,
    this.apiVersion = '0.5',
    this.contractVersion,
    String? Function()? authorization,
  }) : _client = client ?? http.Client(),
       _authorization = authorization;

  /// Server root, e.g. https://host (paths below start with /api/v1).
  final Uri base;
  final String apiVersion;

  /// `X-Contract-Version` (the driver app sends it; without it the server
  /// skips the pickup PIN).
  final String? contractVersion;
  final http.Client _client;
  final String? Function()? _authorization;

  /// `Bearer …` of this side after [signIn]; in memory only.
  String? token;

  static final math.Random _random = math.Random.secure();

  /// 32 hex characters (`Idempotency-Key`, `X-Request-Id`).
  static String key() => List<String>.generate(
    32,
    (_) => _random.nextInt(16).toRadixString(16),
  ).join();

  String? get _auth => token ?? _authorization?.call();

  bool get signedIn => _auth != null;

  Map<String, String> _headers({bool write = false}) => <String, String>{
    'Accept': 'application/json',
    'X-Api-Version': apiVersion,
    'X-Request-Id': key(),
    'X-Contract-Version': ?contractVersion,
    if (write) 'Content-Type': 'application/json',
    if (write) 'Idempotency-Key': key(),
    'Authorization': ?_auth,
  };

  Future<ApiAnswer> get(
    String path, {
    Map<String, String>? query,
    Duration timeout = const Duration(seconds: 30),
  }) => _send(
    () => _client.get(
      base.replace(path: path, queryParameters: query),
      headers: _headers(),
    ),
    timeout,
  );

  Future<ApiAnswer> post(
    String path, [
    Object? body,
    Duration timeout = const Duration(seconds: 30),
  ]) => _send(
    () => _client.post(
      base.replace(path: path),
      headers: _headers(write: true),
      body: jsonEncode(body ?? const <String, Object>{}),
    ),
    timeout,
  );

  Future<ApiAnswer> _send(
    Future<http.Response> Function() call,
    Duration timeout,
  ) async {
    try {
      final response = await call().timeout(timeout);
      Object? body;
      try {
        body = response.body.isEmpty ? null : jsonDecode(response.body);
      } catch (_) {}
      return ApiAnswer(response.statusCode, body);
    } catch (error) {
      return ApiAnswer(0, null, error: error.runtimeType.toString());
    }
  }

  /// Phone sign-in with a staging test number (no SMS, fixed code).
  /// Null when signed in, else why not (never the number or the code).
  Future<String?> signIn({
    required String phone,
    required String code,
    required String app,
  }) async {
    const slow = Duration(seconds: 70);
    final asked = await post('/api/v1/auth/otp/request', {
      'phone': phone,
      'app': app,
    }, slow);
    final session = asked.map?['sessionId'];
    if (!asked.ok || session is! String) {
      return 'code request ${asked.short}';
    }
    final verified = await post('/api/v1/auth/otp/verify', {
      'phone': phone,
      'sessionId': session,
      'code': code,
    }, slow);
    final access = verified.map?['accessToken'];
    if (!verified.ok || access is! String || access.isEmpty) {
      return 'code verify ${verified.short}';
    }
    token = 'Bearer $access';
    return null;
  }

  void close() => _client.close();

  // ---- the trip, any side (own trip only) --------------------------------

  Future<ApiAnswer> trip(String id) =>
      get('/api/v1/trips/${Uri.encodeComponent(id)}');

  Future<ApiAnswer> cancel(String id, int version, String reasonCode) => post(
    '/api/v1/trips/${Uri.encodeComponent(id)}/cancel',
    {'expectedVersion': version, 'reasonCode': reasonCode},
  );

  Future<ApiAnswer> messages(String id) =>
      get('/api/v1/trips/${Uri.encodeComponent(id)}/messages');

  Future<ApiAnswer> sendMessage(String id, String text) =>
      post('/api/v1/trips/${Uri.encodeComponent(id)}/messages', {'text': text});

  Future<ApiAnswer> answerCall(String callId) =>
      post('/api/v1/calls/${Uri.encodeComponent(callId)}/answer');

  Future<ApiAnswer> endCall(String callId, String reason) => post(
    '/api/v1/calls/${Uri.encodeComponent(callId)}/end',
    {'reason': reason},
  );

  /// `POST /trips/{id}/call`: the caller's side starts a call; a second
  /// one answers 409 call_busy with the live call id in `details`.
  Future<ApiAnswer> call(String id) =>
      post('/api/v1/trips/${Uri.encodeComponent(id)}/call');
}

/// The rider's side of a trip over HTTP.
class RiderApi extends MoveraApi {
  RiderApi(super.base, {super.client});

  Future<ApiAnswer> activeTrip() => get('/api/v1/rider/trips/active');

  Future<ApiAnswer> quote({
    required Map<String, Object> pickup,
    required Map<String, Object> dropoff,
    String paymentMethod = 'cash',
    DateTime? scheduledAt,
  }) => post('/api/v1/quotes', {
    'pickup': pickup,
    'dropoff': dropoff,
    'stops': const <Object>[],
    'kind': scheduledAt == null ? 'live' : 'scheduled',
    'scheduledAt': ?scheduledAt?.toUtc().toIso8601String(),
    'paymentMethod': paymentMethod,
  });

  /// GET /rider/config (booking.minAheadMin and the cancel rules).
  Future<ApiAnswer> config() => get('/api/v1/rider/config');

  Future<ApiAnswer> book(
    Map<String, dynamic> quote, {
    String paymentMethod = 'cash',
    DateTime? scheduledAt,
  }) => post('/api/v1/trips', {
    'quoteId': quote['quoteId'],
    'categoryId': quote['categoryId'],
    'pickup': quote['pickup'],
    'dropoff': quote['dropoff'],
    'stops': quote['stops'] ?? const <Object>[],
    'kind': scheduledAt == null ? 'live' : 'scheduled',
    'scheduledAt': ?scheduledAt?.toUtc().toIso8601String(),
    'paymentMethod': paymentMethod,
    // The whole fare in cash: the cash screen must show the fare itself.
    'walletFirst': false,
  });

  Future<ApiAnswer> receipt(String id) =>
      get('/api/v1/trips/${Uri.encodeComponent(id)}/receipt');

  Future<ApiAnswer> history() =>
      get('/api/v1/rider/trips', query: const {'limit': '20'});

  /// GET /rider/trips?kind=scheduled: the rider's booked-for-later rides
  /// (`/rider/trips/active` lists one only once its driver is driving).
  Future<ApiAnswer> scheduledTrips() => get(
    '/api/v1/rider/trips',
    query: const {'kind': 'scheduled', 'limit': '50'},
  );

  /// Ids of the rider's open (non-terminal) trips the contract lists:
  /// the active trip and the booked rides. Null when a read failed (the
  /// caller must not treat "unknown" as "none").
  Future<Set<String>?> openTripIds() async {
    final active = await activeTrip();
    final booked = await scheduledTrips();
    if ((active.status != 200 && active.status != 204) || !booked.ok) {
      return null;
    }
    bool open(Object? t) =>
        t is Map &&
        t['tripId'] is String &&
        !terminalStatuses.contains(t['status']);
    final items = booked.map?['items'];
    return <String>{
      if (open(active.map)) active.map!['tripId'] as String,
      if (items is List)
        for (final t in items)
          if (open(t)) (t as Map)['tripId'] as String,
    };
  }
}

/// Status groups of contract.json TripStatus.
const Set<String> terminalStatuses = <String>{
  'completed',
  'cancelled_by_rider',
  'cancelled_by_driver',
  'cancelled_by_admin',
  'cancelled_by_system',
  'no_show',
  'expired',
  'failed',
};

/// The rider may cancel (POST /trips/{id}/cancel) up to the arrival.
const Set<String> riderCancellable = <String>{
  'requested',
  'searching',
  'offered',
  'accepted',
  'driver_to_pickup',
  'arrived',
};

const Set<String> onBoardStatuses = <String>{
  'rider_onboard',
  'in_trip',
  'approaching_dropoff',
};

/// Money on the wire (`{amountMinor, currency}`) -> (minor, currency).
(int, String)? moneyOf(Object? json) {
  if (json is! Map) return null;
  final minor = json['amountMinor'];
  final currency = json['currency'];
  if (minor is! num || currency is! String) return null;
  return (minor.toInt(), currency);
}

/// The driver's side of a trip over HTTP (G31 rider: the rider app is on
/// the phone, the test plays the driver). Contract openapi.yaml paths;
/// every command sends the version the driver last saw.
class DriverApi extends MoveraApi {
  DriverApi(super.base, {super.client, super.contractVersion});

  Future<ApiAnswer> profile() => get('/api/v1/driver/profile');

  /// `POST /driver/availability {expectedVersion, onlineStatus, location?}`.
  Future<ApiAnswer> availability(
    int version,
    String status, {
    Map<String, Object>? location,
  }) => post('/api/v1/driver/availability', {
    'expectedVersion': version,
    'onlineStatus': status,
    'location': ?location,
  });

  /// `POST /driver/location {fixes, tripId?}` (LocationBatch).
  Future<ApiAnswer> sendFixes(
    List<Map<String, Object>> fixes, {
    String? tripId,
  }) => post('/api/v1/driver/location', {'fixes': fixes, 'tripId': ?tripId});

  /// `GET /driver/offers?status=open`.
  Future<ApiAnswer> openOffers() => get(
    '/api/v1/driver/offers',
    query: const {'status': 'open', 'limit': '50'},
  );

  /// `POST /offers/{offerId}/accept {expectedVersion}`.
  Future<ApiAnswer> acceptOffer(String offerId, int version) => post(
    '/api/v1/offers/${Uri.encodeComponent(offerId)}/accept',
    {'expectedVersion': version},
  );

  /// `GET /driver/reservations?scope=open|accepted`.
  Future<ApiAnswer> reservations(String scope) => get(
    '/api/v1/driver/reservations',
    query: {'scope': scope, 'limit': '50'},
  );

  Future<ApiAnswer> acceptReservation(String tripId, int version) => post(
    '/api/v1/driver/reservations/${Uri.encodeComponent(tripId)}/accept',
    {'expectedVersion': version},
  );

  Future<ApiAnswer> startReservation(String tripId, int version) => post(
    '/api/v1/driver/reservations/${Uri.encodeComponent(tripId)}/start',
    {'expectedVersion': version},
  );

  /// `POST /trips/{id}/<step>` (head-to-pickup | arrive | board | start |
  /// complete) with [version] and [extra] fields.
  Future<ApiAnswer> tripStep(
    String tripId,
    String step,
    int version, [
    Map<String, Object?> extra = const {},
  ]) => post('/api/v1/trips/${Uri.encodeComponent(tripId)}/$step', {
    'expectedVersion': version,
    ...extra,
  });

  Future<ApiAnswer> verifyPin(String tripId, String pin) => post(
    '/api/v1/trips/${Uri.encodeComponent(tripId)}/pin/verify',
    {'pin': pin},
  );

  Future<ApiAnswer> completePreview(String tripId) => get(
    '/api/v1/driver/trips/${Uri.encodeComponent(tripId)}/complete-preview',
  );

  Future<ApiAnswer> rate(String tripId, int stars) => post(
    '/api/v1/trips/${Uri.encodeComponent(tripId)}/rating',
    {'stars': stars},
  );

  /// `POST /driver/trips/{id}/ride-check` (RideCheckReport), answer ok.
  Future<ApiAnswer> answerRideCheck(
    String tripId,
    String checkId,
    Object? trigger,
  ) => post('/api/v1/driver/trips/${Uri.encodeComponent(tripId)}/ride-check', {
    'checkId': checkId,
    'trigger': trigger,
    'at': DateTime.now().toUtc().toIso8601String(),
    'answer': 'ok',
  });
}

/// One GeoFix (contract GeoFix) at ([lat], [lng]) now.
Map<String, Object> geoFix(
  double lat,
  double lng, {
  double speedMps = 0,
  double? heading,
}) => <String, Object>{
  'lat': double.parse(lat.toStringAsFixed(7)),
  'lng': double.parse(lng.toStringAsFixed(7)),
  'accuracy': 5,
  'speedMps': speedMps,
  'heading': ?heading,
  'moving': speedMps > 1,
  'measuredAt': DateTime.now().toUtc().toIso8601String(),
};
