import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/core/observability/http_observability.dart';
import 'package:movera_rider/core/observability/observability.dart';

/// Load-time job (owner 2026-11-03, audit F8): at start the routine log
/// lines wait for the first screen; errors never wait.
void main() {
  late List<String> sent;
  HttpObservabilitySink sink({bool hold = true}) => HttpObservabilitySink(
    baseUrl: 'https://api.test',
    holdRoutineAtStart: hold,
    client: MockClient((request) async {
      sent.add(request.body);
      return http.Response('{}', 202);
    }),
  );

  setUp(() => sent = []);

  test('routine lines wait until released, errors go at once', () {
    fakeAsync((async) {
      final s = sink();
      s.log(TelemetryLevel.info, 'start.one');
      s.log(TelemetryLevel.debug, 'start.two');
      async.flushMicrotasks();
      expect(sent, isEmpty);
      expect(s.holdingRoutine, isTrue);
      s.log(TelemetryLevel.error, 'start.broken');
      async.flushMicrotasks();
      expect(sent, hasLength(1));
      expect(sent.single, contains('start.broken'));
      s.releaseRoutine();
      async.flushMicrotasks();
      expect(s.holdingRoutine, isFalse);
      expect(sent, hasLength(3));
      expect(sent[1], contains('start.one'));
      expect(sent[2], contains('start.two'));
      s.dispose();
    });
  });

  test('held lines go on their own after the limit', () {
    fakeAsync((async) {
      final s = sink();
      s.log(TelemetryLevel.info, 'start.one');
      async.flushMicrotasks();
      expect(sent, isEmpty);
      async.elapse(const Duration(seconds: 31));
      expect(sent, hasLength(1));
      s.dispose();
    });
  });

  test('without the hold nothing changes', () {
    fakeAsync((async) {
      final s = sink(hold: false);
      s.log(TelemetryLevel.info, 'start.one');
      async.flushMicrotasks();
      expect(sent, hasLength(1));
      s.dispose();
    });
  });
}
