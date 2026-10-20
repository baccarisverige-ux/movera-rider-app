import 'package:movera_rider/features/messages/data/messages_repository.dart';
import 'package:movera_rider/features/messages/domain/messages.dart';
import 'package:movera_rider/l10n/l10n.dart';

class MessagesController {
  MessagesController({
    MessagesRepository? store,
    DateTime Function()? now,
  }) : _store = store ?? MessagesRepository(),
       _now = now ?? DateTime.now;

  factory MessagesController.forRide(
    String? rideId, {
    DateTime Function()? now,
  }) {
    final id = rideId?.trim() ?? '';
    return MessagesController(
      store: id.isEmpty ? MessagesRepository() : MessagesRepository.forRide(id),
      now: now,
    );
  }

  final MessagesRepository _store;
  final DateTime Function() _now;

  List<ChatMessage> get messages => _store.messages;
  int get unreadCount => _store.unreadCount;

  /// "Sending messages to your driver isn't available yet." in the app
  /// language.
  static String get sendUnavailableMessage => L10n.current.chatSendUnavailable;

  bool get canSendMessages => false;

  bool send(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return false;

    // Phase 83 deliberately fails closed until a real message transport is
    // connected. Never append a Rider message locally and make it look sent.
    return false;
  }

  /// Adapter seam for a future transport. It never synthesizes Driver/System
  /// messages; callers must provide the authoritative message object.
  void receive(ChatMessage message) => _store.ingest(message);

  void markAllRead() => _store.markAllRead(_now());
}

