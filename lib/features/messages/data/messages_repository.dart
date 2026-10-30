import 'package:flutter/foundation.dart';
import 'package:movera_rider/features/messages/domain/messages.dart';

/// One ride's conversation as this app holds it. Notifies on every change
/// so the Chat screen and the trip screen's unread badge follow it.
class MessagesRepository extends ChangeNotifier {
  MessagesRepository();

  static final Map<String, MessagesRepository> _rideSessions =
      <String, MessagesRepository>{};

  /// Session-scoped conversation for one active ride.
  ///
  /// This intentionally survives closing/reopening the Chat screen in the same
  /// app process, but it is not durable storage and must not be mistaken for a
  /// backend conversation history: on the live wire the server's listing is
  /// merged into it ([merge]).
  factory MessagesRepository.forRide(String rideId) {
    final key = rideId.trim();
    if (key.isEmpty) return MessagesRepository();
    // An ended trip's chat stays closed and empty (v0.18.5 chat.appStorage).
    if (_endedRides.contains(key)) return MessagesRepository().._closed = true;
    return _rideSessions.putIfAbsent(key, MessagesRepository.new);
  }

  /// Trips whose chat ended in this process (ids only, never a message).
  static final Set<String> _endedRides = <String>{};

  /// Drops every ride conversation held in this process (end of a rider's
  /// session).
  static void clearAllSessions() {
    _rideSessions.clear();
    _endedRides.clear();
  }

  /// Contract v0.18.5 `chat.appStorage` (owner 2026-10-30: "Never store
  /// messages between rider or driver in driver app or rider app"): the
  /// trip of [rideId] ended, so its chat is emptied (also on a screen that
  /// still shows it), closed and forgotten. The chat only ever lived in
  /// memory; no copy is written anywhere.
  static void endRide(String rideId) {
    final key = rideId.trim();
    if (key.isEmpty) return;
    _endedRides.add(key);
    final session = _rideSessions.remove(key);
    session?._end();
  }

  /// Every trip ended (no live ride any more): the same for all chats.
  static void endAllRides() {
    final sessions = _rideSessions.values.toList();
    _endedRides.addAll(_rideSessions.keys);
    _rideSessions.clear();
    for (final session in sessions) {
      session._end();
    }
  }

  void _end() {
    _messages.clear();
    _closed = true;
    notifyListeners();
  }

  final List<ChatMessage> _messages = <ChatMessage>[];
  bool _closed = false;

  /// The trip ended (contract v0.13.0 §22): the chat closes at drop-off.
  /// Nothing more can be written; v0.18.5 `chat.appStorage`: nothing stays
  /// to read either ([endRide] empties it).
  bool get closed => _closed;

  void markClosed() {
    if (_closed) return;
    _closed = true;
    notifyListeners();
  }

  List<ChatMessage> get messages => List<ChatMessage>.unmodifiable(_messages);

  int get unreadCount =>
      _messages.where((message) => message.isUnreadForRider).length;

  void add(ChatMessage message) {
    _messages.add(message);
    notifyListeners();
  }

  /// Inbound seam only. It stores transport-authored driver/system messages
  /// exactly as supplied; it never invents a counterpart message.
  void ingest(ChatMessage message) {
    if (message.sender == ChatMessageSender.rider) {
      throw ArgumentError.value(
        message.sender,
        'message.sender',
        'Inbound messages must be driver or system authored.',
      );
    }
    _messages.add(message);
    notifyListeners();
  }

  /// The server's listing of the trip's messages, folded into what is
  /// shown. A message already here (by `messageId`) is kept as it is, read
  /// state included; the rider's own message that this device is still
  /// sending is matched by text and takes the server's id and time rather
  /// than appearing twice.
  void merge(List<ChatMessage> fromServer) {
    var changed = false;
    for (final message in fromServer) {
      final id = message.messageId;
      if (id == null || _indexOfId(id) >= 0) continue;
      final pending = message.fromRider
          ? _indexOfPendingText(message.text)
          : -1;
      if (pending >= 0) {
        _messages[pending] = message.copyWith(
          localId: _messages[pending].localId,
        );
      } else {
        _messages.add(message);
      }
      changed = true;
    }
    if (!changed) return;
    _sortByServerTime();
    notifyListeners();
  }

  /// The server's answer to a send: the copy with [localId] takes its id and
  /// time. When polling already brought that message in, the local copy is
  /// dropped instead, so it is never shown twice.
  void confirm(String localId, ChatMessage sent) {
    final local = _indexOfLocal(localId);
    final existing = sent.messageId == null ? -1 : _indexOfId(sent.messageId!);
    if (existing >= 0 && existing != local) {
      if (local >= 0) _messages.removeAt(local);
    } else if (local >= 0) {
      _messages[local] = sent.copyWith(localId: localId);
    } else {
      _messages.add(sent.copyWith(localId: localId));
    }
    _sortByServerTime();
    notifyListeners();
  }

  void setDelivery(String localId, ChatDelivery delivery) {
    final index = _indexOfLocal(localId);
    if (index < 0 || _messages[index].delivery == delivery) return;
    _messages[index] = _messages[index].copyWith(delivery: delivery);
    notifyListeners();
  }

  void markAllRead(DateTime at) {
    var changed = false;
    for (var i = 0; i < _messages.length; i += 1) {
      final message = _messages[i];
      if (!message.isUnreadForRider) continue;
      _messages[i] = message.copyWith(readAt: at);
      changed = true;
    }
    if (changed) notifyListeners();
  }

  int _indexOfId(String messageId) =>
      _messages.indexWhere((m) => m.messageId == messageId);

  int _indexOfLocal(String localId) =>
      _messages.indexWhere((m) => m.localId == localId);

  int _indexOfPendingText(String text) => _messages.indexWhere(
    (m) =>
        m.fromRider &&
        m.messageId == null &&
        m.delivery != ChatDelivery.sent &&
        m.text == text,
  );

  /// Server-timed messages in server order; the ones this device is still
  /// sending (no server time yet) stay after them, in the order written.
  void _sortByServerTime() {
    final timed = <ChatMessage>[];
    final local = <ChatMessage>[];
    for (final message in _messages) {
      (message.sentAt == null ? local : timed).add(message);
    }
    // Stable: equal times keep their current order.
    final order = {for (var i = 0; i < timed.length; i++) timed[i]: i};
    timed.sort((a, b) {
      final byTime = a.sentAt!.compareTo(b.sentAt!);
      return byTime != 0 ? byTime : order[a]!.compareTo(order[b]!);
    });
    _messages
      ..clear()
      ..addAll(timed)
      ..addAll(local);
  }
}
