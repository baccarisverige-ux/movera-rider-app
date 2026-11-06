import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/utils/request_id.dart';
import 'package:movera_rider/features/calls/domain/trip_call_session.dart';
import 'package:movera_rider/features/messages/domain/trip_call_transport.dart';

/// `POST /trips/{tripId}/call` (contract v0.13.0 §22) and, v0.18.38 §62,
/// the in-app call steps `POST /calls/{callId}/answer|end|signal`.
class ApiTripCall implements TripCallTransport, CallApi {
  ApiTripCall({required ApiClient api}) : _api = api;

  final ApiClient _api;

  String _call(String callId, String step) =>
      '/api/v1/calls/${Uri.encodeComponent(callId)}/$step';

  @override
  Future<TripCall> call(String tripId) async {
    final json = await start(tripId);
    final mode = json['mode'];
    final callId = json['callId'];
    if (mode == 'in_app' && callId is String) {
      final ice = json['ice'];
      final servers = ice is Map ? ice['servers'] : null;
      return TripCall(
        tripId: tripId,
        mode: 'in_app',
        callId: callId,
        ice: servers is List
            ? [for (final s in servers) Map<String, dynamic>.from(s as Map)]
            : const [],
        raw: json,
      );
    }
    final number = json['proxyNumber'];
    if (number is! String || number.trim().isEmpty) {
      throw const FormatException('Missing proxyNumber in the call response');
    }
    return TripCall(tripId: tripId, proxyNumber: number.trim(), raw: json);
  }

  @override
  Future<Map<String, dynamic>> start(String tripId) => _api.post(
    '/api/v1/trips/${Uri.encodeComponent(tripId)}/call',
    body: const <String, dynamic>{},
    // A fresh key per tap: each tap is a new call.
    idempotencyKey: newRequestId(),
  );

  @override
  Future<Map<String, dynamic>> answer(String callId) => _api.post(
    _call(callId, 'answer'),
    body: const <String, dynamic>{},
    idempotencyKey: newRequestId(),
  );

  @override
  Future<void> end(String callId, String reason) => _api.post(
    _call(callId, 'end'),
    body: {'reason': reason},
    idempotencyKey: newRequestId(),
  );

  @override
  Future<void> signal(String callId, Map<String, dynamic> body) => _api.post(
    _call(callId, 'signal'),
    body: body,
    idempotencyKey: newRequestId(),
  );
}
