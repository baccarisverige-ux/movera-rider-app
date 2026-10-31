import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/realtime/api_ride_realtime.dart';
import 'package:movera_rider/features/ride_booking/application/ride_session.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// Checker round 1 on rider G5: the Terms texts equal the contract's, a
/// silent stream counts as dropped, and the booked pickup is kept.
void main() {
  tearDown(() => L10n.use('en'));

  test('the Terms texts are the contract texts in sv, fr and en', () async {
    final contract =
        jsonDecode(await File('contracts/contract.json').readAsString())
            as Map<String, dynamic>;
    final texts =
        ((contract['pickupWaiting'] as Map)['terms'] as Map)['texts'] as Map;
    for (final lang in ['sv', 'fr', 'en']) {
      L10n.use(lang);
      final l = L10n.current;
      String fill(String key, Map<String, String> values) {
        var text = (texts[key] as Map)[lang] as String;
        values.forEach((k, v) => text = text.replaceAll('{$k}', v));
        return text;
      }

      expect(l.termsCancelAfterArrived, fill('cancelAfterArrived', {}));
      expect(
        l.termsFreeWait('3', 'X'),
        fill('freeWait', {'free': '3', 'perMin': 'X'}),
      );
      expect(
        l.termsNoShow('3', 'Y'),
        fill('noShow', {'noShowAfter': '3', 'noShowFee': 'Y'}),
      );
      expect(l.termsPickupMove('200'), fill('pickupMove', {'meters': '200'}));
    }
  });

  test(
    '45 s without a line (no heartbeat) drops the stream: poll + reconnect',
    () {
      fakeAsync((async) {
        final t0 = DateTime.utc(2026, 10, 31, 9);
        var now = t0;
        var reads = 0;
        var streams = 0;
        final rt = ApiRideRealtime(
          api: ApiClient(
            env: const AppEnv(
              flavor: AppFlavor.staging,
              apiBaseUrl: 'https://x.invalid',
            ),
            client: MockClient.streaming((request, _) async {
              if (request.url.path.endsWith('/events')) {
                streams += 1;
                // Open, then silent for ever (a proxy that ate the socket).
                return http.StreamedResponse(
                  StreamController<List<int>>().stream,
                  200,
                );
              }
              reads += 1;
              return http.StreamedResponse(
                Stream.value(
                  utf8.encode(
                    jsonEncode({
                      'tripId': 'trp_1',
                      'status': 'driver_to_pickup',
                      'version': 1,
                      'updatedAt': t0.toIso8601String(),
                    }),
                  ),
                ),
                200,
              );
            }),
          ),
          clock: () => now,
        );
        final sub = rt.subscribe('trp_1').listen((_) {});
        void tick(int s) {
          for (var i = 0; i < s; i++) {
            now = now.add(const Duration(seconds: 1));
            async.elapse(const Duration(seconds: 1));
          }
        }

        async.flushMicrotasks();
        expect(rt.isStreamUp('trp_1'), isTrue);
        tick(44);
        expect(rt.isStreamUp('trp_1'), isTrue);
        expect(reads, 1, reason: 'no poll while the stream is up');
        tick(2);
        expect(rt.isStreamUp('trp_1'), isFalse, reason: 'silent 45 s = down');
        // The stream is tried again after 5 s (it reconnects, so the
        // 10 s poll that ran meanwhile stops again).
        tick(6);
        expect(streams, 2, reason: 'reconnected');
        expect(rt.isStreamUp('trp_1'), isTrue);
        // Silent again: down once more, and the 10 s poll keeps the trip
        // fresh until the next reconnect.
        tick(46);
        expect(rt.isStreamUp('trp_1'), isFalse);
        final before = reads;
        tick(10);
        expect(reads, greaterThan(before), reason: 'the 10 s poll took over');
        sub.cancel();
        rt.dispose();
      });
    },
  );

  test(
    'the booked pickup is kept: a later (moved) pickup never replaces it',
    () {
      final session = RideSession()
        ..observeBookedPickup('trp_1', 59.3293, 18.0686)
        ..observeBookedPickup('trp_1', 59.3305, 18.0686);
      expect(session.bookedPickupOf('trp_1'), (lat: 59.3293, lng: 18.0686));
      session.observeBookedPickup('trp_1', 59.33, 18.07, authoritative: true);
      expect(session.bookedPickupOf('trp_1'), (lat: 59.33, lng: 18.07));
    },
  );
}
