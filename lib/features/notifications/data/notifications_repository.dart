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

  /// rider-51: each label is worked out now from when the push was sent,
  /// so a row from last night reads "Yesterday …" the next morning instead
  /// of the clock it got when it arrived.
  List<AppNotification> all() => List<AppNotification>.unmodifiable([
    for (final item in _items)
      item.at == null ? item : item.copyWith(time: _formatTime(item.at!)),
  ]);

  Stream<List<AppNotification>> watch() => _changes.stream;

  void ingest(PushPayload payload, {required bool read}) {
    // v0.18.5 chat.appStorage: a chat message never becomes a stored line
    // (the server no longer sends trip_message notices; an older one that
    // still arrives is not kept either).
    if (payload.type == 'trip_message') return;
    final title = payload.title?.trim();
    final body = payload.body?.trim();

    // Data-only ride pushes still drive authoritative ride resync, but they do
    // not fabricate user-facing copy for the Notifications feed.
    if ((title == null || title.isEmpty) && (body == null || body.isEmpty)) {
      return;
    }

    final messageId = payload.messageId?.trim();
    if (messageId != null && messageId.isNotEmpty) {
      final existing = _items.indexWhere((item) => item.messageId == messageId);
      if (existing >= 0) {
        if (read && !_items[existing].read) {
          _items[existing] = _items[existing].copyWith(read: true);
          _emit();
        }
        return;
      }
    }

    final at = (payload.sentAt ?? _now()).toLocal();
    // rider-u129: newest sent first. A tray push tapped later (or the
    // cold-start message) is ingested after newer foreground ones and
    // goes below them, not to the top.
    var index = _items.indexWhere((item) {
      final itemAt = item.at;
      return itemAt == null || !itemAt.isAfter(at);
    });
    if (index < 0) index = _items.length;
    _items.insert(
      index,
      AppNotification(
        kind: payload.isRideEvent ? 'ride' : 'info',
        title: title?.isNotEmpty == true ? title! : 'Movera',
        // rider-u128: no body means no second line; the wire type
        // ('ride.driver_arrived') is not text for the rider.
        subtitle: body?.isNotEmpty == true ? body! : '',
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

  /// Contract v0.18.14 `deepFix1.notifications`: `GET /notifications`
  /// gives each notice's title and body in the account's current language
  /// (also a `refund` notice and the trip moments). A notice already here
  /// from its push takes the server's words; one not here is added.
  void syncServer(Map<String, dynamic> page) {
    final items = page['items'];
    if (items is! List) return;
    for (final raw in items) {
      if (raw is! Map) continue;
      final id = raw['notificationId'];
      final title = '${raw['title'] ?? ''}'.trim();
      if (id is! String || id.isEmpty || title.isEmpty) continue;
      if (raw['kind'] == 'trip_message') continue;
      final at = (DateTime.tryParse('${raw['at']}') ?? _now()).toLocal();
      final item = AppNotification(
        kind: '${raw['kind'] ?? 'info'}',
        title: title,
        subtitle: '${raw['body'] ?? ''}'.trim(),
        time: _formatTime(at),
        at: at,
        read: raw['read'] == true,
        messageId: id,
        rideId: raw['tripId'] is String ? raw['tripId'] as String : null,
        deepLink: raw['deepLink'] is String ? raw['deepLink'] as String : null,
      );
      final existing = _items.indexWhere((i) => i.messageId == id);
      if (existing >= 0) {
        _items[existing] = item.copyWith(
          read: item.read || _items[existing].read,
        );
        continue;
      }
      var index = _items.indexWhere((i) => i.at == null || !i.at!.isAfter(at));
      if (index < 0) index = _items.length;
      _items.insert(index, item);
    }
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
    // rider-50: calendar days, counted on UTC midnights. Local midnights
    // are 23 or 25 hours apart across a DST change, so inDays came out one
    // short (yesterday read as today on the day after spring-forward).
    final today = DateTime.utc(now.year, now.month, now.day);
    final day = DateTime.utc(time.year, time.month, time.day);
    final daysAgo = today.difference(day).inDays;
    if (daysAgo <= 0) return clock;
    if (daysAgo == 1) return L10n.current.notifYesterday(clock);
    final date = L10n.formatDate(time, 'd MMM');
    if (time.year != now.year) return '$date ${time.year} $clock';
    return '$date $clock';
  }
}
