import 'package:movera_rider/core/notifications/push_payload.dart';
import 'package:movera_rider/core/web/web_push_open_io.dart'
    if (dart.library.js_interop) 'package:movera_rider/core/web/web_push_open_web.dart';

/// Contract v0.18.3 (owner decision R7): a tap on a web push. The service
/// worker (`web/firebase-messaging-sw.js`) posts `movera-push-open` to an
/// open tab, or opens the app with `?movera_push=…&movera_kind=…
/// &movera_link=…`; FlutterFire has no tap event on the web.
Stream<PushPayload> webPushOpens() => platformWebPushOpens();

/// The push this page was opened from, read once.
PushPayload? takeWebLaunchPush() => platformTakeWebLaunchPush();

/// The launch push in [query] (the page address's query), or null.
PushPayload? pushFromLaunchQuery(Map<String, String> query) {
  final id = query['movera_push'];
  if (id == null || id.trim().isEmpty) return null;
  return pushFromOpenMessage({
    'notificationId': id,
    'kind': query['movera_kind'],
    'deepLink': query['movera_link'],
  });
}

/// The worker's `movera-push-open` message data, as a payload.
PushPayload? pushFromOpenMessage(Map<String, Object?> data) {
  final kind = data['kind'];
  final id = data['notificationId'];
  try {
    return PushPayload.fromMap({
      'type': kind is String && kind.trim().isNotEmpty ? kind : 'notification',
      'deepLink': data['deepLink'],
      'messageId': id,
    });
  } on FormatException {
    return null;
  }
}
