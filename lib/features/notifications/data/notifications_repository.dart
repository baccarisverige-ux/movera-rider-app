import 'dart:async';

import 'package:movera_rider/core/notifications/push_payload.dart';
import 'package:movera_rider/features/notifications/domain/notifications.dart';
import 'package:movera_rider/l10n/l10n.dart';

class NotificationsRepository {
  NotificationsRepository({DateTime Function()? now})
      : _now = now ?? DateTime.now;

  static final NotificationsRepository shared = NotificationsRepository();

  final DateTime Function() _now;
  final List<AppNotification> _items = <AppNotification>[];
  final StreamController<List<AppNotification>> _changes =
      StreamController<List<AppNotification>>.broadcast();

  List<AppNotification> all() => List<AppNotification>.unmodifiable(_items);

  Stream<List<AppNotification>> watch() => _changes.stream;

  void ingest(PushPayload payload, {required bool read}) {
    final title = payload.title?.trim();
    final body = payload.body?.trim();

    // Data-only ride pushes still drive authoritative ride resync, but they do
    // not fabricate user-facing copy for the Notifications feed.
    if ((title == null || title.isEmpty) && (body == null || body.isEmpty)) {
      return;
    }

    final messageId = payload.messageId?.trim();
    if (messageId != null && messageId.isNotEmpty) {
      final existing = _items.indexWhere(
        (item) => item.messageId == messageId,
      );
      if (existing >= 0) {
        if (read && !_items[existing].read) {
          _items[existing] = _items[existing].copyWith(read: true);
          _emit();
        }
        return;
      }
    }

    final at = (payload.sentAt ?? _now()).toLocal();
    _items.insert(
      0,
      AppNotification(
        kind: payload.isRideEvent ? 'ride' : 'info',
        title: title?.isNotEmpty == true ? title! : 'Movera',
        subtitle: body?.isNotEmpty == true ? body! : payload.type,
        time: _formatTime(at),
        at: at,
        read: read,
        messageId: messageId,
        rideId: payload.rideId,
        deepLink: payload.deepLink,
      ),
    );
    _emit();
  }

  void markRead(String? messageId) {
    final id = messageId?.trim();
    if (id == null || id.isEmpty) return;
    final index = _items.indexWhere((item) => item.messageId == id);
    if (index < 0 || _items[index].read) return;
    _items[index] = _items[index].copyWith(read: true);
    _emit();
  }

  /// Empties the feed at the end of a rider's session.
  void clear() {
    _items.clear();
    _emit();
  }

  void clearForTest() => clear();

  void _emit() {
    if (_changes.isClosed) return;
    _changes.add(all());
  }

  /// FLOW-18: only today's items show just the time; older ones say which
  /// day ("Yesterday 14:05", "3 Oct 14:05", "3 Oct 2025 14:05").
  String _formatTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    final clock = '$hour:$minute';
    final now = _now().toLocal();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(time.year, time.month, time.day);
    final daysAgo = today.difference(day).inDays;
    if (daysAgo <= 0) return clock;
    if (daysAgo == 1) return L10n.current.notifYesterday(clock);
    final date = L10n.formatDate(time, 'd MMM');
    if (time.year != now.year) return '$date ${time.year} $clock';
    return '$date $clock';
  }
}
