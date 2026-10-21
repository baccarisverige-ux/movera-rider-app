// Firebase Cloud Messaging service worker for Movera web push.
//
// Inert by default: nothing registers this file unless the build has Firebase
// configured. FirebasePushService only calls getToken (which registers this
// worker) when every MOVERA_FIREBASE_* define and the VAPID key are set; the
// demo build sets none, so on the demo this file is served but never runs.
//
// It deliberately loads no Firebase SDK and holds no project config: the page
// owns the FCM subscription, and this worker hands a push to a visible tab
// (FirebaseMessaging.onMessage), shows a notification otherwise, and opens
// the app when one is tapped. Ride state stays authoritative from the
// backend and is reconciled when the app opens.

self.addEventListener('install', function() {
  self.skipWaiting();
});

self.addEventListener('activate', function(event) {
  event.waitUntil(self.clients.claim());
});

function moveraReadPush(event) {
  if (!event.data) return null;
  try {
    return event.data.json();
  } catch (_) {
    return null;
  }
}

self.addEventListener('push', function(event) {
  var payload = moveraReadPush(event);
  if (!payload || typeof payload !== 'object') return;
  var notification = payload.notification;
  var data = payload.data && typeof payload.data === 'object' ? payload.data : {};
  event.waitUntil(
    self.clients.matchAll({type: 'window', includeUncontrolled: true}).then(function(clients) {
      var visible = clients.some(function(client) {
        return client.visibilityState === 'visible';
      });
      if (visible) {
        // rider-u243: a visible Movera tab shows the update in the app. The
        // browser hands pushes only to this worker, and the page's
        // FirebaseMessaging.onMessage fires only for a payload posted to it
        // in the Firebase SDK's own format (what its messaging worker does).
        payload.isFirebaseMessaging = true;
        payload.messageType = 'push-received';
        clients.forEach(function(client) {
          client.postMessage(payload);
        });
        return undefined;
      }
      // Only FCM-shaped payloads with a visible notification are shown.
      if (!notification || typeof notification !== 'object') return undefined;
      return self.registration.showNotification(String(notification.title || 'Movera'), {
        body: notification.body ? String(notification.body) : '',
        icon: 'icons/Icon-192.png',
        data: data,
        tag: data.rideId ? 'movera-ride-' + data.rideId : undefined
      });
    })
  );
});

self.addEventListener('notificationclick', function(event) {
  event.notification.close();
  var target = new URL('./', self.registration.scope).href;
  event.waitUntil(
    self.clients.matchAll({type: 'window', includeUncontrolled: true}).then(function(clients) {
      for (var i = 0; i < clients.length; i += 1) {
        if (clients[i].url.indexOf(target) === 0 && 'focus' in clients[i]) {
          return clients[i].focus();
        }
      }
      return self.clients.openWindow ? self.clients.openWindow(target) : undefined;
    })
  );
});
