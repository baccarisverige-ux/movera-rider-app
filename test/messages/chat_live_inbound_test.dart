import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/messages/application/messages_controller.dart';
import 'package:movera_rider/features/messages/data/messages_repository.dart';
import 'package:movera_rider/features/messages/domain/messages.dart';
import 'package:movera_rider/features/messages/domain/trip_messages_transport.dart';
import 'package:movera_rider/features/messages/presentation/chat.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// Contract v0.5.4: on the live wire the open Chat screen polls the trip's
/// messages, so a driver's message appears without the rider doing
/// anything, and the rider's own message is sent and confirmed.
class _FakeTripMessages implements TripMessagesTransport {
  final List<ChatMessage> onServer = [];
  final List<String> sentTexts = [];
  int listings = 0;
  bool failSends = false;

  @override
  Future<List<ChatMessage>> list(String tripId) async {
    listings += 1;
    return List.of(onServer);
  }

  @override
  Future<ChatMessage> send(
    String tripId,
    String text, {
    required String idempotencyKey,
  }) async {
    sentTexts.add(text);
    if (failSends) throw StateError('down');
    final message = ChatMessage(
      text: text,
      sender: ChatMessageSender.rider,
      sentAt: DateTime.utc(2026, 10, 26, 8, 40, onServer.length),
      messageId: 'msg_${onServer.length + 1}',
      readAt: DateTime.utc(2026, 10, 26, 8, 40),
    );
    onServer.add(message);
    return message;
  }
}

void main() {
  late _FakeTripMessages server;
  late MessagesController controller;

  setUp(() {
    server = _FakeTripMessages();
    controller = MessagesController(
      store: MessagesRepository(),
      transport: server,
      rideId: 'trp_1',
    );
  });

  Future<void> pumpChat(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, __) => MaterialApp(
          home: Chat(
            driverName: 'Erik',
            rideId: 'trp_1',
            controller: controller,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('a driver message polled while the chat is open appears and '
      'is read', (tester) async {
    await pumpChat(tester);
    expect(find.text('No messages yet'), findsOneWidget);
    expect(server.listings, 1);

    server.onServer.add(
      ChatMessage(
        text: 'I am outside',
        sender: ChatMessageSender.driver,
        sentAt: DateTime.utc(2026, 10, 26, 8, 35),
        messageId: 'msg_d1',
      ),
    );
    await tester.pump(MessagesController.chatPollInterval);
    await tester.pump();

    expect(server.listings, 2);
    expect(find.text('I am outside'), findsOneWidget);
    expect(find.text('No messages yet'), findsNothing);
    // The rider is looking at it: no unread badge waits on the trip screen.
    expect(controller.unreadCount, 0);

    // Support's messages are shown under Movera's name.
    server.onServer.add(
      ChatMessage(
        text: 'We have told your driver',
        sender: ChatMessageSender.support,
        sentAt: DateTime.utc(2026, 10, 26, 8, 36),
        messageId: 'msg_s1',
      ),
    );
    await tester.pump(MessagesController.chatPollInterval);
    await tester.pump();
    expect(find.text('We have told your driver'), findsOneWidget);
    expect(find.text('Movera'), findsOneWidget);

    // Closing the screen stops the polling.
    await tester.pumpWidget(const SizedBox.shrink());
    final after = server.listings;
    await tester.pump(MessagesController.chatPollInterval * 3);
    expect(server.listings, after);
  });

  testWidgets('the rider sends from the composer; a failed send stays '
      'retryable with its text', (tester) async {
    await pumpChat(tester);
    // On the live wire the composer is live: no "unavailable" banner.
    expect(find.text(MessagesController.sendUnavailableMessage), findsNothing);
    expect(find.bySemanticsLabel('Send message'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Are you close?');
    await tester.tap(find.bySemanticsLabel('Send message'));
    await tester.pump();
    await tester.pump();

    expect(server.sentTexts, ['Are you close?']);
    expect(find.text('Are you close?'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty);
    expect(controller.messages.single.messageId, 'msg_1');
    // The server's `at`, on the app's 24-hour clock in local time.
    expect(
      find.text(L10n.formatTime(DateTime.utc(2026, 10, 26, 8, 40).toLocal())),
      findsOneWidget,
    );

    server.failSends = true;
    await tester.enterText(find.byType(TextField), 'Still there?');
    await tester.tap(find.bySemanticsLabel('Send message'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Still there?'), findsOneWidget);
    expect(find.text('Not sent. Tap to retry.'), findsOneWidget);
    expect(find.text("Your message wasn't sent. Try again."), findsOneWidget);
    expect(controller.messages.last.delivery, ChatDelivery.failed);

    server.failSends = false;
    await tester.tap(find.text('Still there?'));
    await tester.pump();
    await tester.pump();

    expect(server.sentTexts, ['Are you close?', 'Still there?', 'Still there?']);
    expect(find.text('Not sent. Tap to retry.'), findsNothing);
    expect(controller.messages.last.delivery, ChatDelivery.sent);
    expect(controller.messages, hasLength(2));
  });
}
