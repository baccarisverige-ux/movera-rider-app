import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/messages/application/messages_controller.dart';
import 'package:movera_rider/features/messages/domain/messages.dart';

void main() {
  test('rider send stays local draft-only when transport is unavailable', () {
    final controller = MessagesController();

    expect(controller.canSendMessages, isFalse);
    expect(controller.send('Are you close?'), isFalse);
    expect(controller.messages, isEmpty);
  });

  test(
    'authoritative driver/system messages can be ingested without fabrication',
    () {
      final controller = MessagesController(
        now: () => DateTime(2026, 9, 22, 9, 9),
      );

      controller.receive(
        ChatMessage(
          text: 'I am outside',
          sender: ChatMessageSender.driver,
          sentAt: DateTime(2026, 9, 22, 9, 8),
        ),
      );
      controller.receive(
        ChatMessage(
          text: 'Your driver has arrived',
          sender: ChatMessageSender.system,
          kind: ChatMessageKind.systemEvent,
          sentAt: DateTime(2026, 9, 22, 9, 9),
        ),
      );

      expect(controller.messages, hasLength(2));
      expect(controller.unreadCount, 2);
      expect(controller.messages.first.fromRider, isFalse);
      expect(controller.messages.last.isSystem, isTrue);

      controller.markAllRead();
      expect(controller.unreadCount, 0);
      expect(
        controller.messages.every((message) => message.readAt != null),
        isTrue,
      );
    },
  );

  test('blank messages are rejected', () {
    final controller = MessagesController();

    expect(controller.send('   '), isFalse);
    expect(controller.messages, isEmpty);
  });
}
