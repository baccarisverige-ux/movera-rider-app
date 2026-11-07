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
Future<Map<String, dynamic>> _push(
  String visibility, {
  Map<String, Object?>? payload,
  bool click = false,
}) async {
  final run = await Process.run('node', [
    'test/web/firebase_messaging_sw_harness.js',
    'web/firebase-messaging-sw.js',
    visibility,
    jsonEncode(
      payload ??
          {
            'from': '1234',
            'fcmMessageId': 'm1',
            'notification': {'title': 'Driver arrived', 'body': 'Volvo XC60'},
            'data': {'type': 'driver_arrived', 'rideId': 'r1'},
          },
    ),
    if (click) 'click',
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

  // Contract v0.18.3 (owner decision R7): movera-server's web pushes are
  // data messages; a tap opens the app on the notice.
  const serverPush = {
    'from': '1234',
    'data': {
      'notificationId': 'ntf_1',
      'kind': 'trip_message',
      'deepLink': 'movera://ride/r9',
      'title': 'Nytt meddelande',
      'body': 'Jag står vid entrén',
    },
  };

  test('R7: a server data push is shown with its own title and body; a tap '
      'tells the open tab which notice', () async {
    final run = await _push('hidden', payload: serverPush, click: true);
    expect(run['shown'], [
      allOf(
        containsPair('title', 'Nytt meddelande'),
        containsPair('body', 'Jag står vid entrén'),
        containsPair('tag', 'ntf_1'),
      ),
    ]);
    expect(run['posted'], [
      {
        'type': 'movera-push-open',
        'notificationId': 'ntf_1',
        'kind': 'trip_message',
        'deepLink': 'movera://ride/r9',
      },
    ]);
    expect(run['focused'], ['https://rider.test/']);
  }, skip: _hasNode() ? false : 'node is not installed');

  test('R7: with no tab open a tap opens the app with the notice in the '
      'address', () async {
    final run = await _push('none', payload: serverPush, click: true);
    expect(run['opened'], [
      'https://rider.test/?movera_push=ntf_1&movera_kind=trip_message'
          '&movera_link=movera%3A%2F%2Fride%2Fr9',
    ]);
  }, skip: _hasNode() ? false : 'node is not installed');
}
