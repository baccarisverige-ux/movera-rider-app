// Firebase Cloud Messaging service worker for Movera web push.
//
// Inert by default: nothing registers this file unless push is configured.
// FirebasePushService only calls getToken (which registers this worker) with
// Firebase settings: the build's MOVERA_FIREBASE_* defines or, since contract
// v0.18.3 (owner decision R7), the public settings the server gives at run
// time (GET /push/config?app=rider). The demo build has neither.
//
// movera-server sends web pushes as data messages: { notificationId, kind,
// deepLink, title, body }, already in the rider's language.
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
      // A notification block, or the server's data message (v0.18.3, R7).
      var shown = notification && typeof notification === 'object' ? notification : null;
      if (!shown && data.notificationId && data.title) shown = {title: data.title, body: data.body};
      if (!shown) return undefined;
      return self.registration.showNotification(String(shown.title || 'Movera'), {
        body: shown.body ? String(shown.body) : '',
        icon: 'icons/Icon-192.png',
        data: data,
        tag: data.rideId ? 'movera-ride-' + data.rideId : (data.notificationId || undefined)
      });
    })
  );
});

// A tap opens the app on the notice (contract v0.18.3, R7): an open tab gets
// a movera-push-open message, else the app opens with ?movera_push=<id>.
self.addEventListener('notificationclick', function(event) {
  event.notification.close();
  var target = new URL('./', self.registration.scope).href;
  var data = event.notification.data || {};
  var open = {
    type: 'movera-push-open',
    notificationId: String(data.notificationId || ''),
    kind: String(data.kind || data.type || ''),
    deepLink: String(data.deepLink || '')
  };
  event.waitUntil(
    self.clients.matchAll({type: 'window', includeUncontrolled: true}).then(function(clients) {
      for (var i = 0; i < clients.length; i += 1) {
        if (clients[i].url.indexOf(target) === 0 && 'focus' in clients[i]) {
          if (open.notificationId) clients[i].postMessage(open);
          return clients[i].focus();
        }
      }
      var url = open.notificationId
        ? target + '?movera_push=' + encodeURIComponent(open.notificationId) +
          '&movera_kind=' + encodeURIComponent(open.kind) +
          '&movera_link=' + encodeURIComponent(open.deepLink)
        : target;
      return self.clients.openWindow ? self.clients.openWindow(url) : undefined;
    })
  );
});
