import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/core/observability/http_observability.dart';
import 'package:movera_rider/core/observability/observability.dart';

/// Audit Phase 7, request budget: measured on the live web build against the
/// e2e server, the trip screens sent 30 ride polls and 18 telemetry posts a
/// minute, because every answered API call was also a telemetry line. One
/// minute of polling must now cost no telemetry request; failed calls still
/// go out.
void main() {
  test('a minute of answered ride polls sends no telemetry', () async {
    final paths = <String>[];
    final sink = HttpObservabilitySink(
      baseUrl: 'https://api.movera.example',
      client: MockClient((request) async {
        paths.add(request.url.path);
        return http.Response('', 202);
      }),
    );
    for (var i = 0; i < 30; i++) {
      sink.log(
        TelemetryLevel.info,
        'api.GET',
        extra: {'path': '/api/v1/rides/trp_1', 'status': 200},
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(paths, isEmpty);
    expect(sink.droppedCount, 0, reason: 'skipped, not counted as dropped');

    sink.log(
      TelemetryLevel.info,
      'api.GET',
      extra: {'path': '/api/v1/rides/trp_1', 'status': 503},
    );
    sink.log(TelemetryLevel.info, 'ride.restore.cold');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(paths, hasLength(2), reason: 'a failed call and real events');
    sink.dispose();
  });
}
