// Runs the Home lock script from web_overlay_web.dart against a model of
// browser history plus the Flutter web engine's SingleEntryBrowserHistory
// (engine/src/flutter/lib/web_ui/lib/src/engine/navigation/history.dart),
// presses Back at Home and prints, as JSON, what happened.
//
// node home_lock_history_harness.js <web_overlay_web.dart>
'use strict';
const fs = require('fs');
const vm = require('vm');

const source = fs.readFileSync(process.argv[2], 'utf8');
const script = /\.\.text = r'''\n([\s\S]*?)'''/.exec(source)[1];

// Browser: one document, a list of same-document entries, async go().
const entries = [{state: null, url: 'https://rider.test/'}];
let index = 0;
let leftSite = false;
let popstates = 0;
const tasks = [];
const listeners = [];
const history = {
  get state() { return entries[index].state; },
  get length() { return entries.length; },
  pushState(state, _t, url) {
    entries.splice(index + 1);
    entries.push({state: clone(state), url: url || entries[index].url});
    index++;
  },
  replaceState(state, _t, url) {
    entries[index] = {state: clone(state), url: url || entries[index].url};
  },
  go(n) { tasks.push(() => traverse(n)); },
  back() { this.go(-1); },
};
const location = {get href() { return entries[index].url; }};
const window = {
  history, location,
  addEventListener(type, fn, options) {
    const capture = options === true || !!(options && options.capture);
    listeners.push({type, fn, capture});
  },
};
const clone = (v) => (v == null ? null : JSON.parse(JSON.stringify(v)));
function traverse(n) {
  const target = index + n;
  if (target < 0) { leftSite = true; return; }
  if (target >= entries.length || target === index) return;
  index = target;
  popstates++;
  let stopped = false;
  const event = {state: history.state, stopImmediatePropagation() { stopped = true; }};
  // At the target, capture listeners run before bubble ones (DOM spec).
  for (const l of [...listeners.filter((l) => l.capture), ...listeners.filter((l) => !l.capture)]) {
    if (l.type === 'popstate' && !stopped) l.fn(event);
  }
}

// Engine: SingleEntryBrowserHistory with the default hash strategy.
let routeName = '/';
let homeRoot = true;
const popRoutes = [];
const isOrigin = (s) => !!s && s.origin === true;
const isFlutter = (s) => !!s && s.flutter === true;
const pushFlutter = () => history.pushState({flutter: true}, 'flutter', '#' + routeName);
history.replaceState({origin: true, state: history.state}, 'origin', '');
pushFlutter();
window.addEventListener('popstate', (event) => {
  if (isOrigin(event.state)) {
    pushFlutter();
    popRoutes.push(routeName);
    // At Home-at-root the framework answers with SystemNavigator.pop: exit.
    if (homeRoot) leftSite = true;
  } else if (isFlutter(event.state)) {
    popRoutes.push('pushRoute ' + routeName);
  } else {
    routeName = '/';
    history.go(-1);
  }
});

const document = {
  documentElement: {classList: {toggle() {}}},
};
const ctx = Object.assign(window, {document});
ctx.window = ctx;
vm.runInNewContext(script, ctx);

function settle() {
  for (let i = 0; i < 500 && tasks.length; i++) tasks.shift()();
  return tasks.length === 0;
}

// A few Home round trips (open a sheet, close it), then Back at Home.
for (let i = 0; i < 4; i++) { ctx.moveraSetHomeLock(false); ctx.moveraSetHomeLock(true); }
const lengthAtHome = history.length;
history.back();
const settled = settle();
const atHome = {settled, popstates, leftSite, popRoutes: [...popRoutes], lengthAtHome, top: history.state};
// Away from Home (lock off) Back must reach the engine as popRoute again.
ctx.moveraSetHomeLock(false);
homeRoot = false;
popRoutes.length = 0;
history.back();
settle();
process.stdout.write(JSON.stringify({atHome, awayPopRoutes: popRoutes}));
