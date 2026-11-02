import 'package:movera_rider/core/notifications/push_payload.dart';
import 'package:movera_rider/features/notifications/data/notifications_repository.dart';
import 'package:movera_rider/features/notifications/domain/notifications.dart';

class NotificationsController {
  NotificationsController({
    NotificationsRepository? store,
    Future<Map<String, dynamic>> Function(String path)? fetch,
  }) : _store = store ?? NotificationsRepository.shared,
       _fetch = fetch;

  final NotificationsRepository _store;
  final Future<Map<String, dynamic>> Function(String path)? _fetch;

  static const serverPath = '/api/v1/notifications?limit=50';

  /// v0.18.14: the server's list, in the account's language (refund
  /// notices and trip moments included). Quietly keeps the feed as it is
  /// when the server cannot answer.
  Future<void> refreshFromServer() async {
    final fetch = _fetch;
    if (fetch == null) return;
    try {
      _store.syncServer(await fetch(serverPath));
    } catch (_) {
      // Saved / kept as it is: the next read shows the server's state.
    }
  }

  List<AppNotification> feed() => _store.all();

  Stream<List<AppNotification>> watch() => _store.watch();

  void ingest(PushPayload payload, {required bool read}) {
    _store.ingest(payload, read: read);
  }

  void markRead(String? messageId) => _store.markRead(messageId);
}
