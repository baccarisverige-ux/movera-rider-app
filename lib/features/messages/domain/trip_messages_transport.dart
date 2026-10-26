import 'package:movera_rider/features/messages/domain/messages.dart';

/// The trip chat on the wire (contract v0.5.4, `/trips/{tripId}/messages`).
///
/// Only the live wire has one; the demo's mock transport has no chat
/// server, so its controller is built without a transport and the Chat
/// screen stays read-only as before.
abstract interface class TripMessagesTransport {
  /// `POST /trips/{tripId}/messages { text }`. Returns the server's copy
  /// (`messageId`, `at`). The same [idempotencyKey] on a retry replays the
  /// committed message instead of sending a second one.
  Future<ChatMessage> send(
    String tripId,
    String text, {
    required String idempotencyKey,
  });

  /// `GET /trips/{tripId}/messages`: every message of the trip the server
  /// has, oldest first.
  Future<List<ChatMessage>> list(String tripId);
}
