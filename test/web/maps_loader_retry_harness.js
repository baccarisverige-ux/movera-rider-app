// Runs index.html's moveraLoadGoogleMaps: asks once, the script fails to
// load, asks again; prints how many Maps scripts were added.
//
// node maps_loader_retry_harness.js <index.html>
'use strict';
const fs = require('fs');
const vm = require('vm');

const html = fs.readFileSync(process.argv[2], 'utf8');
const start = html.indexOf('    window.moveraLoadGoogleMaps = function() {');
const end = html.indexOf('\n    };', start) + '\n    };'.length;
if (start < 0) throw new Error('loader not found');
const added = [];
const head = {
  appendChild(node) { node.parentNode = head; added.push(node); },
  removeChild(node) { node.parentNode = null; },
};
const sandbox = {
  document: {head, createElement: () => ({})},
  moveraMapsSrc: 'https://maps.example.test/js',
};
sandbox.window = sandbox;
vm.createContext(sandbox);
vm.runInContext(html.slice(start, end), sandbox);
sandbox.moveraLoadGoogleMaps();
sandbox.moveraLoadGoogleMaps(); // still loading: no second script
const first = added[0];
if (typeof first.onerror === 'function') first.onerror(new Error('net'));
sandbox.moveraLoadGoogleMaps(); // after the failure
process.stdout.write(JSON.stringify({
  scripts: added.length,
  firstRemoved: first.parentNode == null,
}));
