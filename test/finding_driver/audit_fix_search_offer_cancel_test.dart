import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/finding_driver/data/finding_driver_repository.dart';
import 'package:movera_rider/features/ride_booking/application/ride_session.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The in-process backend, with a hook for the cancel request and a hold
/// on the offer raise's answer (the server has already applied it).
class _Backend extends http.BaseClient {
  _Backend(this.inner);

  final InProcessMockClient inner;
  FutureOr<http.StreamedResponse?> Function()? onCancel;
  Completer<void>? holdRaise;
  final raiseApplied = Completer<void>();
  int cancelPosts = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method == 'POST' && request.url.path.endsWith('/cancel')) {
      cancelPosts += 1;
      final response = await onCancel?.call();
      if (response != null) return response;
    }
    final response = await inner.send(request);
    final hold = holdRaise;
    if (request.method == 'PATCH' && hold != null) {
      raiseApplied.complete();
      await hold.future;
    }
    return response;
  }
}

/// R4.9: an offer raise or a queued cancel racing the search (rider-u96,
/// rider-u103).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InProcessMockClient server;
  late _Backend backend;
  late ApiClient api;
  late MockRideRealtime realtime;
  late FindingDriverController controller;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RideSnapshotStore.epoch = 0;
    FindingDriverController.active = null;
    server = InProcessMockClient();
    server.rides['r1'] = {
      'id': 'r1',
      'status': 'findingDriver',
      'price': 259,
      'pickupLat': 59.3,
      'pickupLng': 18.0,
    };
    backend = _Backend(server);
    api = ApiClient(client: backend);
    realtime = MockRideRealtime(assignAfter: const Duration(days: 1), api: api);
    controller = FindingDriverController(
      realtime: realtime,
      ride: RideSession()..rideId = 'r1',
      store: FindingDriverRepository(),
      priceBumpAfter: Duration.zero,
      api: api,
    );
    controller.start(
      snapshot: RideSnapshot(
        status: RideStatus.findingDriver,
        savedAt: DateTime.now(),
        pickupAddress: 'A',
        destinationAddress: 'B',
        pickupLat: 59.3,
        pickupLng: 18.0,
        destinationLat: 59.4,
        destinationLng: 18.1,
        rideType: 'Movera',
        price: 259,
        paymentMethod: 'Apple Pay',
        rideId: 'r1',
      ),
      onTick: (_) {},
      onMatched: () {},
    );
  });

  tearDown(() {
    controller.dispose();
    realtime.dispose();
  });

  test('rider-u96: a raise the server applied while a refused cancel was in '
      'flight is the fare shown and saved', () async {
    backend.holdRaise = Completer<void>();
    final raising = controller.confirmPriceIncrease(20);
    await backend.raiseApplied.future;

    // The rider cancels; the server refuses: the raise changed the trip.
    backend.onCancel = () => http.StreamedResponse(
      Stream.value(
        utf8.encode(
          jsonEncode({'code': 'version_mismatch', 'retryable': false}),
        ),
      ),
      409,
      headers: {'content-type': 'application/json'},
    );
    expect(await controller.cancelSearch(), SearchCancelResult.stale);

    backend.holdRaise!.complete();
    expect(await raising, isTrue);
    expect(controller.currentPrice, 279);
    expect(controller.offerConfirmation, 'Updated offer: 279 kr');
    expect((await RideSnapshotStore.read())?.price, 279);
  });
}
