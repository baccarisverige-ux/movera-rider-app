import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:movera_rider/core/notifications/push_payload.dart';
import 'package:movera_rider/core/web/web_push_open.dart';
import 'package:web/web.dart' as web;

Stream<PushPayload> platformWebPushOpens() {
  late StreamController<PushPayload> controller;
  JSFunction? listener;
  controller = StreamController<PushPayload>(
    onListen: () {
      listener = ((web.Event event) {
        final data = (event as web.MessageEvent).data;
        if (data == null || !data.isA<JSObject>()) return;
        final object = data as JSObject;
        String? text(String key) {
          final value = object.getProperty<JSAny?>(key.toJS);
          return value != null && value.isA<JSString>()
              ? (value as JSString).toDart
              : null;
        }

        if (text('type') != 'movera-push-open') return;
        final payload = pushFromOpenMessage({
          'notificationId': text('notificationId'),
          'kind': text('kind'),
          'deepLink': text('deepLink'),
        });
        if (payload != null) controller.add(payload);
      }).toJS;
      try {
        web.window.navigator.serviceWorker.addEventListener(
          'message',
          listener,
        );
      } catch (_) {
        // No service workers here: no taps to hear.
      }
    },
    onCancel: () {
      try {
        web.window.navigator.serviceWorker.removeEventListener(
          'message',
          listener,
        );
      } catch (_) {
        // The listener went with the page.
      }
    },
  );
  return controller.stream;
}

bool _launchTaken = false;

PushPayload? platformTakeWebLaunchPush() {
  if (_launchTaken) return null;
  _launchTaken = true;
  final payload = pushFromLaunchQuery(Uri.base.queryParameters);
  if (payload == null) return null;
  try {
    final clean = Uri.base.replace(queryParameters: const {}).toString();
    web.window.history.replaceState(null, '', clean.replaceAll('?#', '#'));
  } catch (_) {
    // Keeping the query is harmless.
  }
  return payload;
}
