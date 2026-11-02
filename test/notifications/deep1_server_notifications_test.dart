import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/notifications/push_payload.dart';
import 'package:movera_rider/features/notifications/application/notifications_controller.dart';
import 'package:movera_rider/features/notifications/data/notifications_repository.dart';
import 'package:movera_rider/features/notifications/presentation/notifications.dart';

/// Contract v0.18.14 `deepFix1.notifications`: the bell list is read from
/// `GET /notifications`, whose words follow the account's language; a
/// refund notice is in it.
void main() {
  testWidgets('the server\'s words replace the push\'s; a refund notice is '
      'shown with its own mark', (tester) async {
    final store = NotificationsRepository(now: () => DateTime(2026, 11, 2, 12));
    // The push came while the account was in English.
    store.ingest(
      PushPayload.fromMap({
        'kind': 'trip_driver_arrived',
        'notificationId': 'ntf_1',
      }, title: 'Your driver is here'),
      read: false,
    );
    final asked = <String>[];
    final controller = NotificationsController(
      store: store,
      fetch: (path) async {
        asked.add(path);
        return {
          'items': [
            {
              'notificationId': 'ntf_1',
              'kind': 'trip_driver_arrived',
              'title': 'Din förare är här',
              'body': '',
              'at': '2026-11-02T10:00:00Z',
              'read': false,
            },
            {
              'notificationId': 'ntf_2',
              'kind': 'refund',
              'title': 'Återbetalning',
              'body': '45 kr tillbaka på din resa',
              'at': '2026-11-02T10:30:00Z',
              'read': false,
            },
          ],
        };
      },
    );
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, __) =>
            MaterialApp(home: NotificationScreen(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();
    expect(asked, [NotificationsController.serverPath]);
    expect(find.text('Your driver is here'), findsNothing);
    expect(find.text('Din förare är här'), findsOneWidget);
    expect(find.text('45 kr tillbaka på din resa'), findsOneWidget);
    expect(find.byKey(const ValueKey('notification-refund')), findsOneWidget);
    expect(store.all(), hasLength(2));
  });
}
