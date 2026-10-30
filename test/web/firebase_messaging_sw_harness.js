// Runs a service worker file in a fake worker scope with one window
// client, delivers one push and prints, as JSON, what the tab received
// (postMessage) and what the system tray showed (showNotification).
//
// node firebase_messaging_sw_harness.js <worker.js> <visible|hidden|none> <payload json> [click]
//
// With `click` the first shown notification is then tapped; `none` has no
// open tab (contract v0.18.3, R7).
'use strict';
const fs = require('fs');
const vm = require('vm');

const [workerPath, visibility, payload, action] = process.argv.slice(2);
const focused = [];
const opened = [];
const listeners = {};
const posted = [];
const shown = [];
const client = {
  url: 'https://rider.test/',
  visibilityState: visibility,
  postMessage: (message) => posted.push(message),
  focus: async () => { focused.push(client.url); },
};
const self = {
  addEventListener: (type, listener) => { listeners[type] = listener; },
  skipWaiting: () => {},
  clients: {
    matchAll: async () => (visibility === 'none' ? [] : [client]),
    claim: async () => {},
    openWindow: async (url) => { opened.push(url); },
  },
  registration: {
    scope: 'https://rider.test/',
    showNotification: async (title, options) => { shown.push({title, ...options}); },
  },
};
vm.runInNewContext(fs.readFileSync(workerPath, 'utf8'), {self, URL});

let pending = Promise.resolve();
listeners.push({
  data: {json: () => JSON.parse(payload)},
  waitUntil: (promise) => { pending = promise; },
});
pending
  .then(() => {
    if (action !== 'click' || shown.length === 0) return undefined;
    let tapped = Promise.resolve();
    listeners.notificationclick({
      notification: {data: shown[0].data, close: () => {}},
      waitUntil: (promise) => { tapped = promise; },
    });
    return tapped;
  })
  .then(() => process.stdout.write(JSON.stringify({posted, shown, focused, opened})));
