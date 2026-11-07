// Runs index.html's main inline script (heading / motion permission part)
// in a model of iOS Safari, where DeviceOrientationEvent.requestPermission
// shows the Motion & Orientation prompt. Taps the page (not the "my
// position" button), then arms the prompt as the button does and taps
// again; prints how many prompts each step asked for.
//
// node heading_prompt_harness.js <index.html>
'use strict';
const fs = require('fs');
const vm = require('vm');

const html = fs.readFileSync(process.argv[2], 'utf8');
const marker = 'window.moveraNeedsOrientationPermission';
const at = html.indexOf(marker);
const start = html.lastIndexOf('<script>', at) + '<script>'.length;
const end = html.indexOf('</script>', at);
const script = html.slice(start, end);

const listeners = [];
let prompts = 0;
const target = {
  addEventListener(type, fn) { listeners.push({type, fn}); },
  removeEventListener(type, fn) {
    const i = listeners.findIndex((l) => l.type === type && l.fn === fn);
    if (i >= 0) listeners.splice(i, 1);
  },
};
let clock = 1000;
const sandbox = {
  console, Promise, setTimeout, clearTimeout, JSON, Math, String, Number,
  URL,
  Date: {now: () => clock},
  navigator: {userAgent: 'iPhone'},
  document: {
    baseURI: 'https://rider.test/app/',
    addEventListener() {}, removeEventListener() {},
    visibilityState: 'visible',
  },
  DeviceOrientationEvent: {
    requestPermission: () => { prompts += 1; return new Promise(() => {}); },
  },
  DeviceMotionEvent: {requestPermission: () => new Promise(() => {})},
  ...{},
};
sandbox.addEventListener = target.addEventListener;
sandbox.removeEventListener = target.removeEventListener;
sandbox.window = sandbox;
vm.createContext(sandbox);
vm.runInContext(script, sandbox);

function tap() {
  clock += 1000;
  for (const type of ['pointerdown', 'touchstart', 'touchend', 'click']) {
    for (const l of listeners.filter((x) => x.type === type)) l.fn({type});
  }
}
const out = {};
tap(); // a tap anywhere (Where to?, the menu, the map)
out.plainTap = prompts;
const armed = typeof sandbox.moveraArmHeadingFromGesture === 'function';
if (armed) sandbox.moveraArmHeadingFromGesture(); // the "my position" tap
tap(); // the rest of that same tap
out.afterMyPosition = prompts;
tap(); // a later tap anywhere
out.laterTap = prompts;
process.stdout.write(JSON.stringify(out));
