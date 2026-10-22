// Runs a service worker file in a fake worker scope with one window
// client, delivers one push and prints, as JSON, what the tab received
// (postMessage) and what the system tray showed (showNotification).
//
// node firebase_messaging_sw_harness.js <worker.js> <visible|hidden> <payload json>
'use strict';
const fs = require('fs');
const vm = require('vm');

const [workerPath, visibility, payload] = process.argv.slice(2);
const listeners = {};
const posted = [];
const shown = [];
const client = {
  url: 'https://rider.test/',
  visibilityState: visibility,
  postMessage: (message) => posted.push(message),
};
const self = {
  addEventListener: (type, listener) => { listeners[type] = listener; },
  skipWaiting: () => {},
  clients: {matchAll: async () => [client], claim: async () => {}},
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
pending.then(() => process.stdout.write(JSON.stringify({posted, shown})));
