import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/messages/application/messages_controller.dart';
import 'package:movera_rider/features/messages/data/messages_repository.dart';
import 'package:movera_rider/features/messages/domain/chat_options.dart';
import 'package:movera_rider/features/messages/domain/messages.dart';
import 'package:movera_rider/features/messages/domain/trip_messages_transport.dart';
import 'package:movera_rider/features/messages/presentation/chat.dart';
import 'package:movera_rider/l10n/l10n.dart';

class _Chat implements TripMessagesTransport, TripChatExtras {
  final List<String> sent = [];

  @override
  Future<ChatOptions> options(String tripId) async =>
      const ChatOptions(maxLength: 100);
  @override
  Future<List<ChatMessage>> list(String tripId) async => const [];
  @override
  Future<ChatMessage> send(
    String tripId,
    String text, {
    required String idempotencyKey,
  }) async {
    sent.add(text);
    return ChatMessage(
      text: text,
      sender: ChatMessageSender.rider,
      messageId: 'msg_${sent.length}',
    );
  }

  @override
  Future<ChatMessage> sendQuickReply(
    String tripId,
    ChatQuickReply reply,
    String text, {
    required String idempotencyKey,
  }) => throw UnimplementedError();
  @override
  Future<ChatTranslation> translate(
    String tripId,
    String messageId,
    String to, {
    bool auto = false,
  }) => throw UnimplementedError();
}

/// Rules REMINDERS row 29 (contract §78 `CountryRules.chat.maxLength`,
/// 100–2000; the server answers 400 message_too_long): the rider's chat
/// input takes at most maxLength characters and longer text is never sent.
void main() {
  setUp(() {
    MessagesRepository.clearAllSessions();
    L10n.use('en');
  });

  testWidgets('the chat input stops at the country maxLength', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final transport = _Chat();
    final controller = MessagesController.forRide(
      'trp_max',
      transport: transport,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) => MaterialApp(
          home: Chat(
            driverName: 'Erik',
            rideId: 'trp_max',
            controller: controller,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.options.maxLength, 100);

    await tester.enterText(find.byType(TextField), 'a' * 150);
    await tester.pump();
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text.length, 100);

    // Text longer than maxLength that reaches the controller is not sent.
    expect(controller.send('b' * 101), isFalse);
    expect(controller.send('c' * 100), isTrue);
    await tester.pumpAndSettle();
    expect(transport.sent, ['c' * 100]);
  });
}
