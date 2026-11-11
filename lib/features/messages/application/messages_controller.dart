import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/core/api/idempotency.dart';
import 'package:movera_rider/core/logging/app_log.dart';
import 'package:movera_rider/core/sound/app_tones.dart';
import 'package:movera_rider/core/utils/request_id.dart';
import 'package:movera_rider/features/messages/data/messages_repository.dart';
import 'package:movera_rider/features/messages/data/api_trip_messages.dart';
import 'package:movera_rider/features/messages/domain/chat_options.dart';
import 'package:movera_rider/features/messages/domain/messages.dart';
import 'package:movera_rider/features/messages/domain/trip_messages_transport.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// One screen's handle on a ride's conversation. Notifies when the
/// conversation changes (a send, a confirmation, an inbound message from the
/// trip stream).
class MessagesController extends ChangeNotifier {
  MessagesController({
    MessagesRepository? store,
    DateTime Function()? now,
    TripMessagesTransport? transport,
    String? rideId,
  }) : _store = store ?? MessagesRepository(),
       _now = now ?? DateTime.now,
       _transport = transport,
       _rideId = rideId?.trim() ?? '' {
    _store.addListener(_onStore);
  }

  /// The conversation of [rideId], shared by every screen of this process.
  /// With a [transport] (the live wire) the rider can send and the server's
  /// messages are read once and then arrive on the trip stream; without one (the demo) the chat stays read-only.
  factory MessagesController.forRide(
    String? rideId, {
    DateTime Function()? now,
    TripMessagesTransport? transport,
  }) {
    final id = rideId?.trim() ?? '';
    return MessagesController(
      store: id.isEmpty ? MessagesRepository() : MessagesRepository.forRide(id),
      now: now,
      transport: id.isEmpty ? null : transport,
      rideId: id,
    );
  }

  final MessagesRepository _store;
  final DateTime Function() _now;
  final TripMessagesTransport? _transport;
  final String _rideId;
  bool _refreshing = false;
  ChatOptions _options = ChatOptions.fallback;
  bool _optionsRead = false;
  bool _disposed = false;

  void _onStore() {
    notifyListeners();
    _autoTranslate();
  }

  /// Told when a send fails (the server refused it or never answered), so
  /// the screen can say so; the message stays in the list as not sent.
  void Function(ChatMessage message, Object error)? onSendFailed;

  List<ChatMessage> get messages => _store.messages;
  int get unreadCount => _store.unreadCount;

  /// "Sending messages to your driver isn't available yet." in the app
  /// language.
  static String get sendUnavailableMessage => L10n.current.chatSendUnavailable;

  bool get canSendMessages => _transport != null && !isClosed;

  /// The chat closed at drop-off (contract v0.13.0 §22).
  bool get isClosed => _store.closed;

  /// The trip ended: the rider can read the history but not write.
  void markClosed() => _store.markClosed();

  /// Closes the chat of [rideId] for every screen of this process (the trip
  /// ended, or the server answered 409 chat_closed).
  static void closeRide(String rideId) {
    final id = rideId.trim();
    if (id.isEmpty) return;
    // v0.18.5 chat.appStorage: the chat lives only during the trip.
    MessagesRepository.endRide(id);
  }

  /// Shows the message at once and sends it. False when there is nothing
  /// to send or no transport to send it on (the demo): nothing is appended
  /// locally to look sent.
  bool send(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return false;
    // §78 `maxLength`: longer text is refused by the server.
    if (text.length > _options.maxLength) return false;
    if (_transport == null || isClosed) return false;
    final local = ChatMessage(
      text: text,
      sender: ChatMessageSender.rider,
      localId: newRequestId(),
      delivery: ChatDelivery.sending,
    );
    _store.add(local);
    unawaited(_deliver(local));
    return true;
  }

  /// Sends a message the server never took, under the same idempotency key
  /// as the first try (ARCH-4), so a send that did arrive is not repeated.
  Future<void> retry(ChatMessage message) async {
    final localId = message.localId;
    if (localId == null || message.delivery != ChatDelivery.failed) return;
    _store.setDelivery(localId, ChatDelivery.sending);
    final chip = message.quickReplyId;
    final reply = chip == null
        ? null
        : _options.quickReplies.where((r) => r.id == chip).firstOrNull;
    await _deliver(message, quickReply: reply, extras: _extras);
  }

  Future<void> _deliver(
    ChatMessage local, {
    ChatQuickReply? quickReply,
    TripChatExtras? extras,
  }) async {
    final transport = _transport;
    final localId = local.localId;
    if (transport == null || localId == null) return;
    try {
      // One key per message written on this device: a retry replays the
      // same send (contract: a different body under the same key is a
      // 409, so the key is never shared between messages).
      final key = stableIdempotencyKey('message', '$_rideId/$localId');
      final sent = quickReply != null && extras != null
          ? await extras.sendQuickReply(
              _rideId,
              quickReply,
              local.text,
              idempotencyKey: key,
            )
          : await transport.send(_rideId, local.text, idempotencyKey: key);
      if (_disposed) return;
      _store.confirm(localId, sent);
    } catch (error) {
      if (_disposed) return;
      // 409 invalid_transition, reason chat_closed: the trip has ended.
      if (error is ApiError && error.reason == 'chat_closed') markClosed();
      AppLog.warning(
        'messages.send_failed',
        extra: {'rideId': _rideId, 'error': error.toString()},
      );
      _store.setDelivery(localId, ChatDelivery.failed);
      onSendFailed?.call(local, error);
    }
  }

  /// Adapter seam for the demo. It never synthesizes Driver/System
  /// messages; callers must provide the authoritative message object.
  void receive(ChatMessage message) => _store.ingest(message);

  void markAllRead() => _store.markAllRead(_now());

  /// v0.18.56 §78 `chat.stream`: one `message` event of the trip stream
  /// (`RealtimeEvent.message`), folded into that trip's conversation. The
  /// unread badge and the open chat follow it; nothing polls. A new
  /// message from the driver plays Movera's message sound while the
  /// country's `chat.sound` is on (REMINDERS row 28).
  static void ingestStreamMessage(String tripId, Map<String, dynamic> raw) {
    final id = tripId.trim();
    if (id.isEmpty) return;
    final message = ChatMessageWire.fromJson(raw);
    if (message == null) return;
    final store = MessagesRepository.forRide(id);
    final known =
        message.messageId != null &&
        store.messages.any((m) => m.messageId == message.messageId);
    store.merge([message]);
    if (!known &&
        message.sender != ChatMessageSender.rider &&
        (_soundByRide[id] ?? ChatOptions.fallback.sound)) {
      unawaited(AppTones.playChatMessage());
    }
  }

  /// The last `chat.sound` read per trip (options are read per screen,
  /// stream messages arrive without one).
  static final Map<String, bool> _soundByRide = <String, bool>{};

  @visibleForTesting
  static void debugResetSound() => _soundByRide.clear();

  /// Tests: what [loadOptions] would keep for [rideId].
  @visibleForTesting
  static void debugSetSound(String rideId, bool on) =>
      _soundByRide[rideId] = on;

  /// The chat settings of the trip's country (contract v0.18.56 §78);
  /// [ChatOptions.fallback] until [loadOptions] has an answer.
  ChatOptions get options => _options;

  TripChatExtras? get _extras =>
      _transport is TripChatExtras ? _transport as TripChatExtras : null;

  /// `GET /trips/{tripId}/messages/options`, once. A failure keeps the
  /// fallback (no chips, no translate link).
  Future<void> loadOptions() async {
    final extras = _extras;
    if (extras == null || _disposed || _rideId.isEmpty) return;
    try {
      final options = await extras.options(_rideId);
      if (_disposed) return;
      _options = options;
      _optionsRead = true;
      _soundByRide[_rideId] = options.sound;
      notifyListeners();
      _autoTranslate();
    } catch (error) {
      AppLog.warning(
        'messages.options_failed',
        extra: {'rideId': _rideId, 'error': error.toString()},
      );
    }
  }

  /// A quick-reply chip: shown at once in the rider's language and sent with
  /// its id, so the server writes it in the driver's language.
  bool sendQuickReply(ChatQuickReply reply) {
    final extras = _extras;
    if (extras == null || isClosed) return false;
    final text = reply.textIn(L10n.current.localeName);
    final local = ChatMessage(
      text: text,
      sender: ChatMessageSender.rider,
      localId: newRequestId(),
      delivery: ChatDelivery.sending,
      quickReplyId: reply.id,
    );
    _store.add(local);
    unawaited(_deliver(local, quickReply: reply, extras: extras));
    return true;
  }

  /// The translated text of [message] while the rider shows it, else null.
  String? translationOf(ChatMessage message) {
    final id = message.messageId;
    final t = _store.translations;
    if (id == null || !t.showsTranslation(id)) return null;
    return t.shown(id, message.text);
  }

  bool isTranslating(ChatMessage message) {
    final id = message.messageId;
    return id != null && _store.translations.busy(id);
  }

  /// The language a translation goes to: the rider's own app language
  /// (owner A1).
  static String get translateTarget => L10n.current.localeName;

  /// v0.18.64 §85 (owner 2026-11-11: "the language must arrive with the
  /// receiver language"): each message from the driver (or support) is
  /// translated into the rider's language once, as it arrives, when the
  /// trip's options say so (read first) and it is not already in that
  /// language. A failure leaves the original, quietly; `coming_soon`,
  /// `translation_off` or `auto_translate_off` stop it for the trip.
  void _autoTranslate() {
    final extras = _extras;
    final t = _store.translations;
    if (extras == null ||
        _disposed ||
        !_optionsRead ||
        !_options.translatesByItself ||
        t.autoStopped ||
        isClosed) {
      return;
    }
    final target = translateTarget;
    for (final message in _store.messages) {
      final id = message.messageId;
      if (id == null ||
          message.fromRider ||
          message.isSystem ||
          t.autoTried(id) ||
          t.has(id)) {
        continue;
      }
      t.markAutoTried(id);
      if (message.lang == target || !t.start(id)) continue;
      unawaited(_ask(extras, id, auto: true));
    }
  }

  Future<ChatTranslation> _ask(
    TripChatExtras extras,
    String id, {
    required bool auto,
  }) async {
    ChatTranslation answer;
    try {
      answer = await extras.translate(
        _rideId,
        id,
        translateTarget,
        auto: auto,
      );
    } catch (_) {
      answer = const ChatTranslationFailed();
    }
    // The trip may have ended meanwhile: nothing is kept then.
    if (isClosed) return answer;
    final t = _store.translations;
    t.done(id, answer is ChatTranslated ? answer.text : null);
    if (auto &&
        (answer is ChatTranslationComingSoon || answer is ChatTranslationOff)) {
      t.stopAuto();
    }
    _store.translationsChanged();
    return answer;
  }

  /// "Translate to `my language`": `to` is always the rider's own app
  /// language (owner A1). A translation already here (asked by itself or
  /// tapped before) is shown again without a new request. Returns what the
  /// screen should say; null when nothing was asked (one is on its way).
  Future<ChatTranslation?> translate(ChatMessage message) async {
    final id = message.messageId;
    final extras = _extras;
    if (id == null || extras == null) return const ChatTranslationFailed();
    final t = _store.translations;
    if (t.has(id)) {
      t.showTranslation(id);
      _store.translationsChanged();
      return null;
    }
    if (!t.start(id)) return null;
    _store.translationsChanged();
    return _ask(extras, id, auto: false);
  }

  /// "See original": back to the text as written.
  void showOriginal(ChatMessage message) {
    final id = message.messageId;
    if (id == null || !_store.translations.showsTranslation(id)) return;
    _store.translations.showOriginal(id);
    _store.translationsChanged();
  }

  /// One listing from the server (the page, once, when a screen opens),
  /// merged into the conversation; later messages come from the trip
  /// stream. A failed read is logged; the screen keeps what it has.
  Future<void> refresh() async {
    final transport = _transport;
    if (transport == null || _refreshing || _disposed) return;
    _refreshing = true;
    try {
      final fromServer = await transport.list(_rideId);
      if (_disposed) return;
      _store.merge(fromServer);
    } catch (error) {
      AppLog.warning(
        'messages.load_failed',
        extra: {'rideId': _rideId, 'error': error.toString()},
      );
    } finally {
      _refreshing = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _store.removeListener(_onStore);
    super.dispose();
  }
}
