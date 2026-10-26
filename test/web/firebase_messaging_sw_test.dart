import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

bool _hasNode() {
  try {
    return Process.runSync('node', ['--version']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}

/// Delivers one FCM push to web/firebase-messaging-sw.js under node, with a
/// Movera tab that is [visibility] ('visible' or 'hidden').
Future<Map<String, dynamic>> _push(String visibility) async {
  final run = await Process.run('node', [
    'test/web/firebase_messaging_sw_harness.js',
    'web/firebase-messaging-sw.js',
    visibility,
    jsonEncode({
      'from': '1234',
      'fcmMessageId': 'm1',
      'notification': {'title': 'Driver arrived', 'body': 'Volvo XC60'},
      'data': {'type': 'driver_arrived', 'rideId': 'r1'},
    }),
  ]);
  expect(run.exitCode, 0, reason: '${run.stderr}');
  return jsonDecode(run.stdout as String) as Map<String, dynamic>;
}

void main() {
  test('rider-u243: a push for a visible tab reaches FirebaseMessaging.'
      'onMessage; a hidden tab gets a system notification', () async {
    final visible = await _push('visible');
    expect(visible['shown'], isEmpty);
    // The Firebase JS SDK's page side only fires onMessage for this shape.
    expect(visible['posted'], [containsPair('isFirebaseMessaging', true)]);
    final message = (visible['posted'] as List).single as Map;
    expect(message['messageType'], 'push-received');
    expect(message['notification'], {
      'title': 'Driver arrived',
      'body': 'Volvo XC60',
    });
    expect(message['data'], containsPair('rideId', 'r1'));

    final hidden = await _push('hidden');
    expect(hidden['posted'], isEmpty);
    expect(hidden['shown'], [containsPair('title', 'Driver arrived')]);
  }, skip: _hasNode() ? false : 'node is not installed');
}
