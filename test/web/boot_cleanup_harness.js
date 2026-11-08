// Runs index.html's boot clean-up (old service workers and their caches)
// against a model of one origin that serves the rider and the driver app,
// and prints, as JSON, what it removed.
//
// node boot_cleanup_harness.js <index.html>
'use strict';
const fs = require('fs');
const vm = require('vm');

const html = fs.readFileSync(process.argv[2], 'utf8');
const start = html.indexOf('    (function() {\n      var tasks = [];');
const end = html.indexOf('})();', start) + '})();'.length;
if (start < 0 || end < start) throw new Error('clean-up script not found');
const script = html.slice(start, end);

const origin = 'https://baccarisverige-ux.github.io';
const registrations = [
  {scope: `${origin}/movera-rider-app/`, script: `${origin}/movera-rider-app/flutter_service_worker.js`},
  {scope: `${origin}/movera-rider-app/`, script: `${origin}/movera-rider-app/firebase-messaging-sw.js`},
  {scope: `${origin}/Movera-driver-app/`, script: `${origin}/Movera-driver-app/firebase-messaging-sw.js`},
  {scope: `${origin}/Movera-driver-app/`, script: `${origin}/Movera-driver-app/flutter_service_worker.js`},
];
const unregistered = [];
const deleted = [];
const cacheNames = ['flutter-app-cache', 'flutter-temp-cache', 'flutter-app-manifest', 'movera-push-prefs'];

const sandbox = {
  console,
  Promise,
  document: {baseURI: `${origin}/movera-rider-app/`},
  location: {href: `${origin}/movera-rider-app/`},
  URL,
  navigator: {
    serviceWorker: {
      getRegistrations: async () => registrations.map((r) => ({
        scope: r.scope,
        active: {scriptURL: r.script},
        unregister: async () => { unregistered.push(r.script); return true; },
      })),
    },
  },
  caches: {
    keys: async () => cacheNames.slice(),
    delete: async (name) => { deleted.push(name); return true; },
  },
};
sandbox.window = sandbox;
vm.createContext(sandbox);
vm.runInContext(script, sandbox);
setTimeout(() => {
  process.stdout.write(JSON.stringify({unregistered, deleted}));
}, 50);
