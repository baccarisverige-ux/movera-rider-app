import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/contracts/ride_status.dart';
import 'package:movera_rider/features/active_ride/application/active_ride_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Checker on G5 live: a cancel whose answer carries no fee (or never
/// arrives) must not show the previous ride's fee.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('lastCancelFee is cleared before each cancel request', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    var withFee = true;
    final client = _Answer((request) {
      final id = request.url.pathSegments[request.url.pathSegments.length - 2];
      return {
        'tripId': id,
        'status': 'cancelled_by_rider',
        'version': 3,
        if (withFee)
          'cancellation': {
            'actor': 'rider',
            'fee': {'amountMinor': 3500, 'currency': 'SEK'},
            'feeKind': 'cancel',
            'feeStatus': 'owed',
          },
      };
    });
    final controller = ActiveRideController(api: ApiClient(client: client));

    AppScope.instance.ride.restoreFromBackend(
      RideStatus.driverWaiting,
      id: 'ride-1',
    );
    await controller.markCancelled(reasonId: 'something_else');
    expect(controller.lastCancelFee?.fee?.amountMinor, 3500);

    withFee = false;
    client.fail = true;
    AppScope.instance.ride.restoreFromBackend(
      RideStatus.driverWaiting,
      id: 'ride-2',
    );
    await controller.markCancelled(reasonId: 'something_else');
    expect(controller.lastCancelFee, isNull);
  });
}

class _Answer extends http.BaseClient {
  _Answer(this.answer);
  final Map<String, Object?> Function(http.BaseRequest) answer;
  bool fail = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (fail) throw http.ClientException('offline');
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(answer(request)))),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
}
