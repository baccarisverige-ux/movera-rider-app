import 'package:movera_rider/core/notifications/push_payload.dart';
import 'package:movera_rider/features/notifications/data/notifications_repository.dart';
import 'package:movera_rider/features/notifications/domain/notifications.dart';

class NotificationsController {
  NotificationsController({NotificationsRepository? store})
    : _store = store ?? NotificationsRepository.shared;

  final NotificationsRepository _store;

  List<AppNotification> feed() => _store.all();

  Stream<List<AppNotification>> watch() => _store.watch();

  void ingest(PushPayload payload, {required bool read}) {
    _store.ingest(payload, read: read);
  }

  void markRead(String? messageId) => _store.markRead(messageId);
}
