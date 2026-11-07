import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// S8 (2026-11-07): rider #532 gives every push of one trip the same tag
/// `movera-ride-<tripId>` (before #532 real trip pushes had no rideId, so
/// each push had its own notificationId tag). Without `renotify: true` a
/// notice that replaces one with the same tag is shown silently (no sound,
/// no vibration, no banner: Notifications API "alert steps" skipped; Chrome
/// on Android does this). Owner Q1: "always show the notification (banner +
/// sound)". The driver worker (#489) sets renotify for trip notices.
void main() {
  test(
    'a second trip push (driver_arrived after driver_found) alerts again',
    () async {
      final run = await Process.run('node', [
        'test/web/firebase_messaging_sw_harness.js',
        'web/firebase-messaging-sw.js',
        'hidden',
        jsonEncode({
          'data': {
            'kind': 'trip_update',
            'tripId': 't7',
            'moment': 'driver_arrived',
            'notificationId': 'ntf_2',
            'title': 'Votre chauffeur est arrivé',
            'body': 'Préparez-vous à le rejoindre.',
          },
        }),
      ]);
      expect(run.exitCode, 0, reason: '${run.stderr}');
      final shown =
          ((jsonDecode(run.stdout as String) as Map)['shown'] as List).single
              as Map;
      expect(shown['tag'], 'movera-ride-t7');
      expect(shown['renotify'], isTrue, reason: 'options: $shown');
    },
  );
}
