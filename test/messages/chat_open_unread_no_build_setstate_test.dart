import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/app/deferred_screens.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_sheet_bits.dart';
import 'package:movera_rider/features/messages/application/messages_controller.dart';
import 'package:movera_rider/features/messages/data/messages_repository.dart';
import 'package:movera_rider/features/messages/presentation/chat.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/matched_driver.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// Found by the G31 rider device suite: opening the chat from the driver
/// card while a driver message is unread threw "setState() or
/// markNeedsBuild() called during build" (debug). Chat.initState marked
/// the conversation read, the shared store notified at once, and the
/// card's listener called setState while the new route was building.
/// The read mark now lands right after the chat's first frame: no error,
/// and the unread badge still clears once the chat is open.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  tearDown(MessagesRepository.clearAllSessions);

  // The card's unread badge: the count, inside the driver card.
  Finder badge(String n) => find.descendant(
    of: find.byType(WaitingDriverCard),
    matching: find.text(n),
  );

  testWidgets('open chat with an unread message: no build-phase setState, '
      'badge cleared', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // The chat library is deferred; load it now so the tap's next frame
    // builds Chat (a deferred load does not finish on the fake clock).
    await tester.runAsync(loadDeferredScreens);

    const rideId = 'trp_unread_open';
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, __) => MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: WaitingDriverCard(
              driver: const MatchedDriver(id: 'd1', firstName: 'Erik'),
              rideId: rideId,
              onOpenProfile: () {},
              onCall: () {},
              onMore: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    MessagesController.ingestStreamMessage(rideId, {
      'messageId': 'msg_unread_open',
      'tripId': rideId,
      'from': 'driver',
      'text': 'I am outside',
      'at': '2026-10-26T08:35:00Z',
    });
    await tester.pump();
    expect(badge('1'), findsOneWidget);
    expect(MessagesRepository.forRide(rideId).unreadCount, 1);

    await tester.tap(find.text('Message'));
    // Frame by frame: the route, then the (deferred) Chat, whose initState
    // runs inside a build. None may report a build-phase setState.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.takeException(), isNull, reason: 'frame $i');
    }
    expect(find.byType(Chat), findsOneWidget);

    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(MessagesRepository.forRide(rideId).unreadCount, 0);

    Navigator.of(tester.element(find.byType(Chat))).pop();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(Chat), findsNothing);
    expect(badge('1'), findsNothing);
  });
}
