import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:movera_rider/core/api/idempotency.dart';
import 'package:movera_rider/core/logging/app_log.dart';
import 'package:movera_rider/core/utils/request_id.dart';
import 'package:movera_rider/features/messages/data/messages_repository.dart';
import 'package:movera_rider/features/messages/domain/messages.dart';
import 'package:movera_rider/features/messages/domain/trip_messages_transport.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// One screen's handle on a ride's conversation. Notifies when the
/// conversation changes (a send, a confirmation, a polled inbound message).
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
    _store.addListener(notifyListeners);
  }

  /// The conversation of [rideId], shared by every screen of this process.
  /// With a [transport] (the live wire) the rider can send and the server's
  /// messages are polled; without one (the demo) the chat stays read-only.
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

  /// How often the open Chat screen asks the server for new messages. The
  /// live transport polls the trip and never reads the event stream, so
  /// inbound messages are polled too (contract v0.5.4, `listTripMessages`).
  static const chatPollInterval = Duration(seconds: 3);

  /// How often the trip screen asks, for the unread badge on its Message
  /// button.
  static const tripPollInterval = Duration(seconds: 10);

  final MessagesRepository _store;
  final DateTime Function() _now;
  final TripMessagesTransport? _transport;
  final String _rideId;
  Timer? _poll;
  bool _refreshing = false;
  bool _disposed = false;

  /// Told when a send fails (the server refused it or never answered), so
  /// the screen can say so; the message stays in the list as not sent.
  void Function(ChatMessage message, Object error)? onSendFailed;

  List<ChatMessage> get messages => _store.messages;
  int get unreadCount => _store.unreadCount;

  /// "Sending messages to your driver isn't available yet." in the app
  /// language.
  static String get sendUnavailableMessage => L10n.current.chatSendUnavailable;

  bool get canSendMessages => _transport != null;

  /// Shows the message at once and sends it. False when there is nothing
  /// to send or no transport to send it on (the demo): nothing is appended
  /// locally to look sent.
  bool send(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return false;
    if (_transport == null) return false;
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
    await _deliver(message);
  }

  Future<void> _deliver(ChatMessage local) async {
    final transport = _transport;
    final localId = local.localId;
    if (transport == null || localId == null) return;
    try {
      final sent = await transport.send(
        _rideId,
        local.text,
        // One key per message written on this device: a retry replays the
        // same send (contract: a different body under the same key is a
        // 409, so the key is never shared between messages).
        idempotencyKey: stableIdempotencyKey('message', '$_rideId/$localId'),
      );
      if (_disposed) return;
      _store.confirm(localId, sent);
    } catch (error) {
      if (_disposed) return;
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

  /// Asks the server for the trip's messages now and [every] so long from
  /// now on, until [stopPolling] or [dispose]. Nothing happens without a
  /// transport.
  void startPolling(Duration every) {
    if (_transport == null || _disposed) return;
    _poll?.cancel();
    _poll = Timer.periodic(every, (_) => unawaited(refresh()));
    unawaited(refresh());
  }

  void stopPolling() {
    _poll?.cancel();
    _poll = null;
  }

  bool get isPolling => _poll != null;

  /// One listing from the server, merged into the conversation. A failed
  /// read is logged and the next tick asks again; the screen keeps what it
  /// has.
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
        'messages.poll_failed',
        extra: {'rideId': _rideId, 'error': error.toString()},
      );
    } finally {
      _refreshing = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    stopPolling();
    _store.removeListener(notifyListeners);
    super.dispose();
  }
}
