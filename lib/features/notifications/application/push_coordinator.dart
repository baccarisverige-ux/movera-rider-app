import 'dart:async';

import 'package:movera_rider/core/logging/app_log.dart';
import 'package:movera_rider/core/notifications/push_payload.dart';
import 'package:movera_rider/core/notifications/push_service.dart';
import 'package:movera_rider/features/auth/application/user_data_wipe.dart';
import 'package:movera_rider/features/notifications/application/notifications_controller.dart';

typedef RidePushOpener = Future<bool> Function(String rideId);
typedef NotificationsPushOpener = void Function();

class PushCoordinator {
  PushCoordinator({
    required PushService push,
    required RidePushOpener openRide,
    required NotificationsPushOpener openNotifications,
    NotificationsController? notifications,
  }) : _push = push,
       _openRide = openRide,
       _openNotifications = openNotifications,
       _notifications = notifications ?? NotificationsController();

  final PushService _push;
  final RidePushOpener _openRide;
  final NotificationsPushOpener _openNotifications;
  final NotificationsController _notifications;

  StreamSubscription<PushPayload>? _foregroundSub;
  StreamSubscription<PushPayload>? _openedSub;
  bool _started = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;

    _foregroundSub = _push.foregroundMessages.listen(
      _handleForeground,
      onError: (Object error, StackTrace stack) {
        AppLog.error(
          'push.foreground_dispatch_failed',
          error: error,
          stackTrace: stack,
        );
      },
    );
    _openedSub = _push.openedMessages.listen(
      (payload) => unawaited(_handleOpened(payload)),
      onError: (Object error, StackTrace stack) {
        AppLog.error(
          'push.opened_dispatch_failed',
          error: error,
          stackTrace: stack,
        );
      },
    );

    final initial = await _push.takeInitialMessage();
    if (initial != null) {
      await _handleOpened(initial);
    }
  }

  void _handleForeground(PushPayload payload) {
    _notifications.ingest(payload, read: false);
    AppLog.info(
      'push.foreground',
      extra: {'type': payload.type, 'rideId': payload.routedRideId ?? ''},
    );
  }

  Future<void> _handleOpened(PushPayload payload) async {
    // rider-r5-44: the OS tray outlives a sign-out. A notification sent
    // before this rider signed in on the device is the previous rider's:
    // it never enters this rider's feed or routing.
    final sentAt = payload.sentAt;
    final started = sentAt == null
        ? null
        : await UserDataWipe.sessionStartedAt();
    if (sentAt != null && started != null && sentAt.isBefore(started)) {
      AppLog.info('push.opened_before_session', extra: {'type': payload.type});
      return;
    }
    _notifications.ingest(payload, read: true);

    final rideId = payload.routedRideId;
    if (payload.destination == PushDestination.ride && rideId != null) {
      try {
        final handled = await _openRide(rideId);
        if (handled) return;
      } catch (error, stack) {
        AppLog.error(
          'push.ride_open_failed',
          error: error,
          stackTrace: stack,
          extra: {'rideId': rideId},
        );
      }
    }

    _openNotifications();
  }

  Future<void> stop() async {
    await _foregroundSub?.cancel();
    await _openedSub?.cancel();
    _foregroundSub = null;
    _openedSub = null;
    _started = false;
  }
}
