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
  Object? payload,
  bool click = false,
}) async {
  final run = await Process.run('node', [
    'test/web/firebase_messaging_sw_harness.js',
    'web/firebase-messaging-sw.js',
    visibility,
    payload is String
        ? payload
        : jsonEncode(
            payload ??
                {
                  'from': '1234',
                  'fcmMessageId': 'm1',
                  'notification': {
                    'title': 'Driver arrived',
                    'body': 'Volvo XC60',
                  },
                  'data': {'type': 'driver_arrived', 'rideId': 'r1'},
                },
          ),
    if (click) 'click',
  ]);
  expect(run.exitCode, 0, reason: '${run.stderr}');
  return jsonDecode(run.stdout as String) as Map<String, dynamic>;
}

void main() {
  // Owner decision Q1 (2026-11-07, "Toujours afficher"): every push shows a
  // notification, also while the app is on screen. iOS WebKit removes the
  // push subscription after 3 pushes that show none (maxSilentPushCount = 3,
  // finding D1). The visible tab still gets the push in the app (rider-u243).
  test(
    'rider-u243 + Q1: a push for a visible tab reaches FirebaseMessaging.'
    'onMessage and is also shown; a hidden tab gets a system notification',
    () async {
      final visible = await _push('visible');
      expect(visible['shown'], [
        allOf(
          containsPair('title', 'Driver arrived'),
          containsPair('body', 'Volvo XC60'),
          containsPair('tag', 'movera-ride-r1'),
        ),
      ]);
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
    },
    skip: _hasNode() ? false : 'node is not installed',
  );

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
    expect(run['focused'], ['https://apps.test/movera-rider-app/']);
  }, skip: _hasNode() ? false : 'node is not installed');

  test('R7: with no tab open a tap opens the app with the notice in the '
      'address', () async {
    final run = await _push('none', payload: serverPush, click: true);
    expect(run['opened'], [
      'https://apps.test/movera-rider-app/?movera_push=ntf_1&movera_kind=trip_message'
          '&movera_link=movera%3A%2F%2Fride%2Fr9',
    ]);
  }, skip: _hasNode() ? false : 'node is not installed');

  test('Q1: a visible tab with a server data push still shows it', () async {
    final run = await _push('visible', payload: serverPush);
    expect(run['shown'], [containsPair('title', 'Nytt meddelande')]);
    expect(run['posted'], [containsPair('isFirebaseMessaging', true)]);
  }, skip: _hasNode() ? false : 'node is not installed');

  test('Q1: a push with no readable notice still shows a notification '
      '(never a silent push)', () async {
    final empty = await _push('visible', payload: 'NO_DATA');
    expect(empty['shown'], [containsPair('title', 'Movera')]);
    final broken = await _push('hidden', payload: '{not json');
    expect(broken['shown'], [containsPair('title', 'Movera')]);
    final bare = await _push('hidden', payload: {'from': '1234'});
    expect(bare['shown'], [containsPair('title', 'Movera')]);
  }, skip: _hasNode() ? false : 'node is not installed');

  test('D7: a visible driver app tab on the same origin is not the rider '
      'on screen: it gets nothing, the hidden rider tab gets nothing in the '
      'app, the notice is shown', () async {
    final run = await _push('driver-visible');
    expect(run['driverPosted'], isEmpty);
    expect(run['posted'], isEmpty);
    expect(run['shown'], [containsPair('title', 'Driver arrived')]);
  }, skip: _hasNode() ? false : 'node is not installed');

  // Contract 0.18.48: trip pushes carry data {tripId, moment}; rideId is
  // only a read-only legacy alias (CONTRACT.md "Ids"). Each moment of one
  // trip replaces the trip's notice instead of stacking a new one.
  test('a real trip push (tripId + moment) gets the per-trip tag', () async {
    Map<String, Object?> moment(String name, String title) => {
      'from': '1234',
      'data': {
        'notificationId': 'ntf_$name',
        'kind': 'trip_moment',
        'tripId': 't7',
        'moment': name,
        'title': title,
        'body': 'Volvo XC60',
      },
    };
    final arriving = await _push(
      'hidden',
      payload: moment('driver_arriving', 'Votre chauffeur arrive bientôt'),
    );
    final arrived = await _push(
      'visible',
      payload: moment('driver_arrived', 'Votre chauffeur est arrivé'),
    );
    expect(arriving['shown'], [containsPair('tag', 'movera-ride-t7')]);
    expect(arrived['shown'], [containsPair('tag', 'movera-ride-t7')]);
  }, skip: _hasNode() ? false : 'node is not installed');
}
