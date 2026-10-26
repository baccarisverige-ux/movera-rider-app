import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/notifications/push_payload.dart';
import 'package:movera_rider/features/notifications/application/notifications_controller.dart';
import 'package:movera_rider/features/notifications/data/notifications_repository.dart';
import 'package:movera_rider/features/notifications/presentation/notifications.dart';

Future<void> _pump(
  WidgetTester tester,
  NotificationsController controller, {
  required Future<bool> Function(String rideId) openRide,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ScreenUtilInit(
      designSize: const Size(390, 844),
      builder: (_, __) => MaterialApp(
        home: NotificationScreen(controller: controller, openRide: openRide),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('ride notification tap marks read and opens its ride target', (
    tester,
  ) async {
    final store = NotificationsRepository();
    final controller = NotificationsController(store: store);
    controller.ingest(
      const PushPayload(
        type: 'ride.driver_assigned',
        title: 'Driver assigned',
        body: 'Your driver is on the way.',
        messageId: 'phase84-ride',
        rideId: 'ride-84',
      ),
      read: false,
    );

    final opened = <String>[];
    await _pump(
      tester,
      controller,
      openRide: (rideId) async {
        opened.add(rideId);
        return true;
      },
    );

    await tester.tap(find.text('Driver assigned'));
    await tester.pump();

    expect(opened, ['ride-84']);
    expect(store.all().single.read, isTrue);
  });

  testWidgets('notification without usable target only marks read', (
    tester,
  ) async {
    final store = NotificationsRepository();
    final controller = NotificationsController(store: store);
    controller.ingest(
      const PushPayload(
        type: 'account.updated',
        title: 'Account update',
        body: 'Your account changed.',
        messageId: 'phase84-info',
        deepLink: 'https://example.com/not-allowed',
      ),
      read: false,
    );

    var opens = 0;
    await _pump(
      tester,
      controller,
      openRide: (_) async {
        opens += 1;
        return true;
      },
    );

    await tester.tap(find.text('Account update'));
    await tester.pump();

    expect(opens, 0);
    expect(store.all().single.read, isTrue);
  });
}
