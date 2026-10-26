import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/core/notifications/push_payload.dart';
import 'package:movera_rider/features/notifications/application/notifications_controller.dart';
import 'package:movera_rider/features/notifications/data/notifications_repository.dart';
import 'package:movera_rider/features/notifications/presentation/notifications.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// rider-r5-45: an open Notifications screen relabels its times when the
/// app language changes, without waiting for the next push.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  tearDown(() => L10n.use('en'));

  testWidgets('Yesterday follows a language switch', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    L10n.use('en');
    final store = NotificationsRepository(
      now: () => DateTime(2026, 10, 22, 13),
    );
    store.ingest(
      PushPayload(
        type: 'promo',
        title: 'Hello',
        messageId: 'm1',
        sentAt: DateTime(2026, 10, 21, 14, 5),
      ),
      read: true,
    );
    Widget app(String code) => LanguageRebuild(
      code: code,
      child: ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) => MaterialApp(
          home: NotificationScreen(
            controller: NotificationsController(store: store),
          ),
        ),
      ),
    );
    await tester.pumpWidget(app('en'));
    await tester.pump();
    expect(find.text('Yesterday 14:05'), findsOneWidget);

    L10n.use('sv');
    await tester.pumpWidget(app('sv'));
    await tester.pump();
    expect(find.text('I går 14:05'), findsOneWidget);
  });
}
