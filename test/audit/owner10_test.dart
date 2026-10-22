// Owner decision 10 (FIX_PLAN "Owner decisions"): the demo refused booking
// (rider-u29).
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';

/// Counts the stand-in server's answers to `POST /rides/{id}/status`.
class _Counting extends http.BaseClient {
  final inner = InProcessMockClient();
  int statusAnswers = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await inner.send(request);
    if (request.url.path.endsWith('/status')) statusAnswers++;
    return response;
  }
}

Future<void> _until(bool Function() done) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!done() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('rider-u29: a refused accept shows no made-up driver', () async {
    final transport = _Counting();
    final rt = MockRideRealtime(
      assignAfter: const Duration(days: 1),
      api: ApiClient(client: transport),
    );
    addTearDown(rt.dispose);
    final seen = <RideStatus>[];
    // The stand-in server never had this ride: the accept answers 404.
    rt.subscribe('ride_the_server_never_had').listen((e) => seen.add(e.status));
    rt.assignNow();
    await _until(() => transport.statusAnswers > 0 && rt.lastDriver == null);

    expect(transport.statusAnswers, 1);
    expect(rt.lastDriver, isNull);
    expect(rt.lastStatus, RideStatus.findingDriver);
    expect(seen, isNot(contains(RideStatus.driverAssigned)));
  });
}
