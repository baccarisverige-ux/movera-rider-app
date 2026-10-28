import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/utils/request_id.dart';
import 'package:movera_rider/features/messages/domain/trip_call_transport.dart';

/// `POST /trips/{tripId}/call` on the contract wire (v0.13.0 §22).
class ApiTripCall implements TripCallTransport {
  ApiTripCall({required ApiClient api}) : _api = api;

  final ApiClient _api;

  @override
  Future<TripCall> call(String tripId) async {
    final json = await _api.post(
      '/api/v1/trips/${Uri.encodeComponent(tripId)}/call',
      body: const <String, dynamic>{},
      // A fresh key per tap: each tap is a new call.
      idempotencyKey: newRequestId(),
    );
    final number = json['proxyNumber'];
    if (number is! String || number.trim().isEmpty) {
      throw const FormatException('Missing proxyNumber in the call response');
    }
    return TripCall(tripId: tripId, proxyNumber: number.trim());
  }
}
