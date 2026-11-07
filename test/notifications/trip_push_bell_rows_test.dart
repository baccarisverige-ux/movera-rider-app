import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/notifications/push_payload.dart';
import 'package:movera_rider/features/notifications/data/notifications_repository.dart';

/// Contract v0.18.51 §73 (riderTripPushBell, S4 ISSUE 2): the server writes
/// the rider's trip pushes with bell true, so each is also a row of
/// GET /notifications. A trip push the app already showed (foreground,
/// kept under its message id) and the server's row of the same notice
/// (its notificationId) must be ONE bell row, and trip rows must show.
void main() {
  final at = DateTime.utc(2026, 11, 7, 15, 30);

  Map<String, dynamic> serverPage() => {
    'items': [
      {
        'notificationId': 'ntf_77',
        'kind': 'trip_update',
        'title': 'Your driver has arrived',
        'body': 'Get ready to meet your driver.',
        'tripId': 'trp_7',
        'deepLink': 'movera://trips/trp_7',
        'at': at.toIso8601String(),
        'read': false,
      },
    ],
    'nextCursor': null,
  };

  test('the server lists trip pushes in the bell', () {
    final store = NotificationsRepository(now: () => at);
    store.syncServer(serverPage());
    expect(store.all().single.title, 'Your driver has arrived');
  });

  test('a foreground trip push and its server row are one bell row', () {
    final store = NotificationsRepository(now: () => at);
    // As FirebasePushService builds it: the FCM message id and the data.
    final push = PushPayload.fromMap(
      {
        'kind': 'trip_update',
        'notificationId': 'ntf_77',
        'tripId': 'trp_7',
        'moment': 'driver_arrived',
        'deepLink': 'movera://trips/trp_7',
      },
      messageId: '0:1730993400000000%fcm',
      title: 'Your driver has arrived',
      body: 'Get ready to meet your driver.',
      sentAt: at,
    );
    store.ingest(push, read: false);
    store.syncServer(serverPage());
    expect(store.all(), hasLength(1), reason: '${store.all().length} rows');
  });
}
