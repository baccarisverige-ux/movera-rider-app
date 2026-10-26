import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/contracts/wire_time.dart';
import 'package:movera_rider/features/messages/domain/messages.dart';
import 'package:movera_rider/features/messages/domain/trip_messages_transport.dart';

/// The trip chat on the contract wire (openapi.yaml v0.5.4,
/// `sendTripMessage` / `listTripMessages`). Composed only where
/// [ApiClient.contractWire] is true.
class ApiTripMessages implements TripMessagesTransport {
  ApiTripMessages({required ApiClient api, this.pageSize = 50, this.maxPages = 4})
      : _api = api;

  final ApiClient _api;

  /// `limit` per page (the contract's default; at most 200).
  final int pageSize;

  /// How many pages one listing follows through `nextCursor`. A trip chat is
  /// a handful of messages; this only bounds a runaway cursor.
  final int maxPages;

  static String _path(String tripId) =>
      '/api/v1/trips/${Uri.encodeComponent(tripId)}/messages';

  @override
  Future<ChatMessage> send(
    String tripId,
    String text, {
    required String idempotencyKey,
  }) async {
    // Contract `MessageRequest { text }`; the answer is the `Message`.
    final json = await _api.post(
      _path(tripId),
      body: {'text': text},
      idempotencyKey: idempotencyKey,
    );
    final message = ChatMessageWire.fromJson(json);
    if (message == null) {
      throw const FormatException('Missing message in the send response');
    }
    return message;
  }

  @override
  Future<List<ChatMessage>> list(String tripId) async {
    final byId = <String, ChatMessage>{};
    String? cursor;
    for (var page = 0; page < maxPages; page++) {
      final query = cursor == null
          ? 'limit=$pageSize'
          : 'limit=$pageSize&cursor=${Uri.encodeQueryComponent(cursor)}';
      // Contract `MessagePage {items, nextCursor}` (Page<Message>).
      final json = await _api.get('${_path(tripId)}?$query');
      final items = json['items'];
      if (items is List) {
        for (final raw in items) {
          if (raw is! Map) continue;
          final message =
              ChatMessageWire.fromJson(Map<String, dynamic>.from(raw));
          if (message?.messageId case final id?) byId[id] = message!;
        }
      }
      final next = json['nextCursor'];
      if (next is! String || next.isEmpty) break;
      cursor = next;
    }
    final messages = byId.values.toList()
      ..sort((a, b) => a.sentAt!.compareTo(b.sentAt!));
    return messages;
  }
}

/// The contract `Message { messageId, tripId, from, text, at }` as the app's
/// [ChatMessage].
abstract final class ChatMessageWire {
  static ChatMessage? fromJson(Map<String, dynamic> json) {
    final id = json['messageId'];
    final text = json['text'];
    final at = WireTime.tryParse(json['at']);
    final sender = switch (json['from']) {
      'rider' => ChatMessageSender.rider,
      'driver' => ChatMessageSender.driver,
      'support' => ChatMessageSender.support,
      _ => null,
    };
    if (id is! String || id.isEmpty || text is! String || at == null ||
        sender == null) {
      return null;
    }
    return ChatMessage(
      text: text,
      sender: sender,
      sentAt: at,
      messageId: id,
      // The rider's own messages come back read; an inbound one is unread
      // until a screen shows it.
      readAt: sender == ChatMessageSender.rider ? at : null,
    );
  }
}
