import 'package:movera_rider/features/messages/domain/messages.dart';

/// One quick-reply chip (contract v0.18.56 §78, `ChatOptions.quickReplies`):
/// its [id] and its text in sv / fr / en.
class ChatQuickReply {
  const ChatQuickReply({required this.id, required this.text});

  final String id;
  final Map<String, String> text;

  /// The chip in [language], else English, else any text it has.
  String textIn(String language) =>
      text[language] ?? text['en'] ?? (text.isEmpty ? id : text.values.first);
}

/// `GET /trips/{tripId}/messages/options` (contract v0.18.56 §78): the
/// country's chat settings as the rider's side reads them.
class ChatOptions {
  const ChatOptions({
    this.quickReplies = const [],
    this.quickRepliesOn = false,
    this.maxLength = 2000,
    this.sound = true,
    this.sheetAutoOpen = 'new_message',
    this.readAloudDefault = false,
    this.translation = false,
    this.autoTranslate = false,
    this.headerLine = const {},
  });

  /// Before the server answered (or in the demo): no chips, no translate
  /// link; the sheet still opens on a new message (the contract default).
  static const fallback = ChatOptions();

  final List<ChatQuickReply> quickReplies;
  final bool quickRepliesOn;
  final int maxLength;
  final bool sound;

  /// `new_message` | `off` (owner Q82).
  final String sheetAutoOpen;
  final bool readAloudDefault;
  final bool translation;

  /// v0.18.64 §85: messages from the driver arrive translated into the
  /// rider's language ("See original" under them). Absent (an older
  /// server) = off.
  final bool autoTranslate;
  final Map<String, String> headerLine;

  /// The app translates by itself (both switches on).
  bool get translatesByItself => translation && autoTranslate;

  bool get opensSheetOnNewMessage => sheetAutoOpen == 'new_message';

  List<ChatQuickReply> get shownQuickReplies =>
      quickRepliesOn ? quickReplies : const [];

  static Map<String, String> _texts(Object? raw) => raw is Map
      ? {
          for (final e in raw.entries)
            if (e.key is String && e.value is String && '${e.value}'.isNotEmpty)
              e.key as String: e.value as String,
        }
      : const {};

  factory ChatOptions.fromJson(Map<String, dynamic> json) {
    final replies = <ChatQuickReply>[];
    final raw = json['quickReplies'];
    if (raw is List) {
      for (final item in raw) {
        if (item is! Map) continue;
        final id = item['id'];
        final text = _texts(item['text']);
        if (id is String && id.isNotEmpty && text.isNotEmpty) {
          replies.add(ChatQuickReply(id: id, text: text));
        }
      }
    }
    final max = json['maxLength'];
    final open = json['sheetAutoOpen'];
    return ChatOptions(
      quickReplies: replies,
      quickRepliesOn: json['quickRepliesOn'] != false,
      maxLength: max is int && max > 0 ? max : 2000,
      sound: json['sound'] != false,
      sheetAutoOpen: open == 'off' ? 'off' : 'new_message',
      readAloudDefault: json['readAloudDefault'] == true,
      translation: json['translation'] == true,
      autoTranslate: json['autoTranslate'] == true,
      headerLine: _texts(json['headerLine']),
    );
  }
}

/// The answer to a translate request.
sealed class ChatTranslation {
  const ChatTranslation();
}

class ChatTranslated extends ChatTranslation {
  const ChatTranslated(this.text);
  final String text;
}

/// 503 `coming_soon`: no translation provider yet ("Translation coming
/// soon").
class ChatTranslationComingSoon extends ChatTranslation {
  const ChatTranslationComingSoon();
}

/// Any other failure (no answer, an empty text, a refusal).
class ChatTranslationFailed extends ChatTranslation {
  const ChatTranslationFailed();
}

/// v0.18.64 §85: 403 `translation_off` or `auto_translate_off`: the admin
/// turned translation (or the automatic one) off.
class ChatTranslationOff extends ChatTranslation {
  const ChatTranslationOff();
}

/// The §78 additions to the chat wire; only the live wire has them.
abstract interface class TripChatExtras {
  /// `GET /trips/{tripId}/messages/options`.
  Future<ChatOptions> options(String tripId);

  /// `POST /trips/{tripId}/messages { text, quickReplyId }`.
  Future<ChatMessage> sendQuickReply(
    String tripId,
    ChatQuickReply reply,
    String text, {
    required String idempotencyKey,
  });

  /// `POST /trips/{tripId}/messages/translate { messageId, to, auto }`.
  Future<ChatTranslation> translate(
    String tripId,
    String messageId,
    String to, {
    bool auto = false,
  });
}
