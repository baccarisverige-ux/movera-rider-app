// Contract 0.18.49 (owner Q9, server PR #110): a tap on a trip web push
// hands the trip's tripId to the app (open tab: movera-push-open message;
// no tab: ?movera_trip=), so the app opens the ride, not the Notifications
// list (SUP-1). Fail-before on main 8e7c92b7: the worker passed only
// notificationId, kind and deepLink.
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

/// Delivers [payload] to web/firebase-messaging-sw.js under node with a
/// Movera tab that is [visibility] ('hidden', or 'none' for no tab), then
/// taps the shown notification.
Future<Map<String, dynamic>> _tap(
  String visibility,
  Map<String, Object?> payload,
) async {
  final run = await Process.run('node', [
    'test/web/firebase_messaging_sw_harness.js',
    'web/firebase-messaging-sw.js',
    visibility,
    jsonEncode(payload),
    'click',
  ]);
  expect(run.exitCode, 0, reason: '${run.stderr}');
  return jsonDecode(run.stdout as String) as Map<String, dynamic>;
}

void main() {
  // Contract 0.18.49 (owner Q9): the trip push carries tripId; the tap hands
  // it to the app so it opens the ride, not the Notifications list.
  const tripPush = {
    'from': '1234',
    'data': {
      'notificationId': 'ntf_2',
      'kind': 'trip_update',
      'tripId': 'trp_2',
      'deepLink': 'movera://trips/trp_2',
      'title': 'Din förare är framme',
      'body': 'Volvo ABC123',
    },
  };

  test('Q9: a trip push tap tells the open tab the tripId', () async {
    final run = await _tap('hidden', tripPush);
    expect(run['posted'], [
      {
        'type': 'movera-push-open',
        'notificationId': 'ntf_2',
        'kind': 'trip_update',
        'deepLink': 'movera://trips/trp_2',
        'tripId': 'trp_2',
      },
    ]);
  }, skip: _hasNode() ? false : 'node is not installed');

  test('Q9: with no tab open a trip push tap puts the tripId in the '
      'address', () async {
    final run = await _tap('none', tripPush);
    expect(run['opened'], [
      'https://rider.test/?movera_push=ntf_2&movera_kind=trip_update'
          '&movera_link=movera%3A%2F%2Ftrips%2Ftrp_2&movera_trip=trp_2',
    ]);
  }, skip: _hasNode() ? false : 'node is not installed');
}
