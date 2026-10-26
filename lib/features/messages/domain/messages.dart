/// Who wrote a message: the contract's `Message.from` (`rider`, `driver`,
/// `support`) plus the app's own system notes.
enum ChatMessageSender { rider, driver, support, system }

enum ChatMessageKind { text, systemEvent, quickReply, location }

/// Where a rider's own message stands with the server. Inbound messages and
/// confirmed sends are [sent]; a copy shown before the server answered is
/// [sending], and one the server never took is [failed] until it is retried.
enum ChatDelivery { sending, sent, failed }

class ChatMessage {
  const ChatMessage({
    required this.text,
    bool? fromRider,
    ChatMessageSender? sender,
    this.kind = ChatMessageKind.text,
    this.sentAt,
    this.deliveredAt,
    this.readAt,
    this.messageId,
    this.localId,
    this.delivery = ChatDelivery.sent,
  }) : assert(
         sender != null || fromRider != null,
         'A chat message needs an explicit sender.',
       ),
       sender = sender ??
           (fromRider == true
               ? ChatMessageSender.rider
               : ChatMessageSender.driver);

  final String text;
  final ChatMessageSender sender;
  final ChatMessageKind kind;

  /// Time authored by the message source.
  ///
  /// Backend-delivered messages carry their server timestamp (`at`); a
  /// rider's own message gets it when the server confirms it. A missing
  /// timestamp is rendered honestly rather than replaced with a fabricated
  /// clock value.
  final DateTime? sentAt;
  final DateTime? deliveredAt;
  final DateTime? readAt;

  /// The server's `messageId` (contract v0.5.4); null until the server has
  /// seen the message.
  final String? messageId;

  /// This device's id for a message the rider wrote here, so the server's
  /// copy replaces it instead of joining it, and a retry keeps the same
  /// idempotency key.
  final String? localId;
  final ChatDelivery delivery;

  bool get fromRider => sender == ChatMessageSender.rider;
  bool get isSystem => sender == ChatMessageSender.system;
  bool get isUnreadForRider =>
      sender != ChatMessageSender.rider && readAt == null;

  ChatMessage copyWith({
    String? text,
    ChatMessageSender? sender,
    ChatMessageKind? kind,
    DateTime? sentAt,
    DateTime? deliveredAt,
    DateTime? readAt,
    String? messageId,
    String? localId,
    ChatDelivery? delivery,
  }) {
    return ChatMessage(
      text: text ?? this.text,
      sender: sender ?? this.sender,
      kind: kind ?? this.kind,
      sentAt: sentAt ?? this.sentAt,
      deliveredAt: deliveredAt ?? this.deliveredAt,
      readAt: readAt ?? this.readAt,
      messageId: messageId ?? this.messageId,
      localId: localId ?? this.localId,
      delivery: delivery ?? this.delivery,
    );
  }
}
