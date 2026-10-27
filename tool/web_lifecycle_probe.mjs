// Web lifecycle probe: drives a built rider web app through the booking
// lifecycle in Chromium and measures what each screen leaves behind.
//
// Why: on the installed iOS web app the owner saw "crash, blank screen, back
// on Home" at many points of the lifecycle. iOS Safari evicts a page's
// WebGL contexts (around 8-16 per page) and kills the page under memory
// pressure, so this script counts, per screen and across booking cycles:
//   - <canvas> elements in the DOM, split into Flutter's own and Google Maps',
//   - WebGL contexts ever created, still alive (not collected), and lost,
//   - google.maps.Map instances created and still alive after a forced GC,
//     and how many of their container <div>s are detached from the DOM but
//     still retained (the leak this probe was written to prove),
//   - live platform views (<flt-platform-view>) and .gm-style roots,
//   - JS heap (after GC), DOM nodes, JS event listeners, active intervals
//     and requestAnimationFrame loops.
//
// Usage (from the repository root, after `flutter build web`):
//   node tool/web_lifecycle_probe.mjs [--dir build/web] [--cycles 3]
//        [--maps-key KEY] [--out probe.json] [--mode cancel|trip]
//        [--multi-surface] [--raster] [--no-semantics] [--headed] [--shots DIR]
//        [--gps-minute]
//
// Each snapshot also records the frame callbacks drawn while the screen sat
// still (frameCost: count, p95, worst, over 16/32 ms); --gps-minute adds one
// minute on Home with a moving position (audit Phase 7).
//
// --multi-surface forces the rasterizer Flutter uses on Safari and Firefox
// (one WebGL context per display canvas), which is what the iPhone counts.
// --raster strips the cloud Map ID so Google draws raster tiles; without an
// API key vector maps fail anyway, and this keeps Flutter's contexts
// countable on their own. The build must have QA hooks
// (--dart-define=MOVERA_QA=true) for --mode trip (it calls
// window.moveraAssignDriver). Chromium runs with SwiftShader so WebGL works
// headless; numbers are about counts and growth, not speed. The findings
// are in docs/web-lifecycle-investigation.md.
import { createRequire } from 'node:module';
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';

// Playwright is resolved through Node's module path (NODE_PATH or a local
// install), which ESM imports ignore.
const require = createRequire(import.meta.url);
const { chromium } = require('playwright');

const args = process.argv.slice(2);
const opt = (name, fallback) => {
  const i = args.indexOf(`--${name}`);
  return i === -1 ? fallback : args[i + 1];
};
const has = (name) => args.includes(`--${name}`);

const dir = path.resolve(opt('dir', 'build/web'));
const cycles = Number(opt('cycles', '3'));
const mapsKey = opt('maps-key', process.env.MAPS_WEB_API_KEY || '');
const out = opt('out', 'web-lifecycle-probe.json');
const mode = opt('mode', 'cancel');
const shots = opt('shots', '');
const headed = has('headed');
const settle = Number(opt('settle', '2500'));
// Safari and Firefox get Flutter's MultiSurfaceRasterizer (one WebGL context
// per display canvas); Chromium gets the single offscreen context. To count
// what an iPhone counts, --multi-surface forces Safari's path in Chromium.
const multiSurface = has('multi-surface');
const useSemantics = !has('no-semantics');
// --raster strips the cloud Map ID from every map, so Google draws raster
// tiles (no WebGL) and the Flutter contexts can be counted on their own.
const raster = has('raster');

if (shots) fs.mkdirSync(shots, { recursive: true });

const types = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript',
  '.mjs': 'text/javascript',
  '.json': 'application/json',
  '.wasm': 'application/wasm',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.svg': 'image/svg+xml',
  '.ttf': 'font/ttf',
  '.otf': 'font/otf',
  '.woff2': 'font/woff2',
  '.css': 'text/css',
  '.ico': 'image/x-icon',
};

// A static server like GitHub Pages, minus caching: the probe is about the
// page, not the network.
const server = http.createServer((req, res) => {
  const url = new URL(req.url, 'http://localhost');
  let file = path.join(dir, decodeURIComponent(url.pathname));
  if (url.pathname.endsWith('/')) file = path.join(file, 'index.html');
  if (!file.startsWith(dir) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) {
    res.writeHead(404);
    res.end('not found');
    return;
  }
  let body = fs.readFileSync(file);
  const ext = path.extname(file);
  if (path.basename(file) === 'index.html') {
    let html = body.toString('utf8');
    const bootstrap = html.match(/<script src="flutter_bootstrap\.js" defer[^>]*><\/script>/)?.[0] || '<script src="flutter_bootstrap.js" defer></script>';
    if (!html.includes('maps.googleapis.com/maps/api/js')) {
      html = html.replace(
        bootstrap,
        `<script src="https://maps.googleapis.com/maps/api/js?key=${mapsKey}" async defer></script>\n${bootstrap}`,
      );
    }
    body = Buffer.from(html, 'utf8');
  } else if (path.basename(file) === 'flutter_bootstrap.js') {
    // The sandbox cannot reach gstatic: serve CanvasKit from the build.
    body = Buffer.from(
      body.toString('utf8').replace(
        /_flutter\.loader\.load\(\);/,
        `_flutter.loader.load({config: {canvasKitBaseUrl: 'canvaskit/', canvasKitForceMultiSurfaceRasterizer: ${multiSurface}}});`,
      ),
      'utf8',
    );
  }
  res.writeHead(200, {
    'Content-Type': types[ext] || 'application/octet-stream',
    'Cache-Control': 'no-store',
  });
  res.end(body);
});
await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
const base = `http://127.0.0.1:${server.address().port}/`;

// Installed before any page script: counts contexts, maps, timers.
const instrument = () => {
  const P = (window.__probe = {
    contexts: [],
    lostContexts: 0,
    restoredContexts: 0,
    maps: [],
    intervals: new Set(),
    rafLoops: 0,
    rafPending: new Set(),
    frames: [],
    pageErrors: [],
  });
  try {
    localStorage.setItem('flutter.movera_app_language', '"en"');
  } catch (_) {}
  const getContext = HTMLCanvasElement.prototype.getContext;
  HTMLCanvasElement.prototype.getContext = function (type, ...rest) {
    const ctx = getContext.call(this, type, ...rest);
    if (ctx && !this.__probeSeen) {
      this.__probeSeen = true;
      const stack = String(new Error().stack || '');
      const creator = /maps\.googleapis|maps-api-v3/.test(stack) ? 'maps'
        : /canvaskit|dart\.js/.test(stack) ? 'flutter' : 'other';
      P.contexts.push({ type, creator, ref: new WeakRef(this), lost: false, at: performance.now() });
      this.addEventListener('webglcontextlost', () => {
        P.lostContexts += 1;
        const entry = P.contexts.find((c) => c.ref.deref() === this);
        if (entry) entry.lost = true;
      });
      this.addEventListener('webglcontextrestored', () => {
        P.restoredContexts += 1;
      });
    }
    return ctx;
  };
  if (typeof OffscreenCanvas !== 'undefined') {
    const off = OffscreenCanvas.prototype.getContext;
    OffscreenCanvas.prototype.getContext = function (type, ...rest) {
      const ctx = off.call(this, type, ...rest);
      if (ctx && !this.__probeSeen) {
        this.__probeSeen = true;
        P.contexts.push({ type: `offscreen:${type}`, ref: new WeakRef(this), lost: false, at: performance.now() });
      }
      return ctx;
    };
  }
  const setInterval0 = window.setInterval;
  const clearInterval0 = window.clearInterval;
  window.setInterval = function (...a) {
    const id = setInterval0.apply(this, a);
    P.intervals.add(id);
    return id;
  };
  window.clearInterval = function (id) {
    P.intervals.delete(id);
    return clearInterval0.call(this, id);
  };
  const raf0 = window.requestAnimationFrame;
  const caf0 = window.cancelAnimationFrame;
  window.requestAnimationFrame = function (cb) {
    const id = raf0.call(this, (t) => {
      P.rafPending.delete(id);
      // Frame cost: how long the page's frame callback (Flutter's build, layout,
      // paint and CanvasKit draw) ran on the main thread.
      const start = performance.now();
      try {
        cb(t);
      } finally {
        P.frames.push([start, performance.now() - start]);
        if (P.frames.length > 20000) P.frames.splice(0, 10000);
      }
    });
    P.rafPending.add(id);
    return id;
  };
  window.cancelAnimationFrame = function (id) {
    P.rafPending.delete(id);
    return caf0.call(this, id);
  };
  // Map-owner transitions as they happen (the screens hand the map over).
  P.owners = [];
  let lastOwner;
  setInterval0(() => {
    const owner = `${window.moveraMapOwner || ''}/${window.moveraRestoreSurface || ''}`;
    if (owner !== lastOwner) {
      lastOwner = owner;
      P.owners.push([Math.round(performance.now()), owner]);
    }
  }, 100);
  window.addEventListener('error', (e) => P.pageErrors.push(String(e.message) + '\n' + String(e.error && e.error.stack || '').split('\n').slice(0, 6).join('\n')));
  // google.maps arrives async: wrap Map once it is there (the app's own
  // rider_map_camera.js wraps it too; wrapping a wrapper is fine).
  const wrap = () => {
    const g = globalThis.google;
    if (!g || !g.maps || typeof g.maps.Map !== 'function' || g.maps.Map.__probeWrapped) return false;
    const Native = g.maps.Map;
    const Wrapped = new Proxy(Native, {
      construct(target, a) {
        if (window.__probeRaster && a[1] && 'mapId' in a[1]) {
          a = [a[0], { ...a[1], mapId: undefined }, ...a.slice(2)];
        }
        const map = Reflect.construct(target, a);
        P.maps.push({ div: new WeakRef(a[0]), map: new WeakRef(map), id: a[0]?.id || '', at: performance.now() });
        return map;
      },
    });
    Wrapped.__probeWrapped = true;
    g.maps.Map = Wrapped;
    return true;
  };
  const poll = setInterval0(() => {
    if (wrap()) clearInterval0(poll);
  }, 20);
};

const readState = () => {
  const P = window.__probe;
  // Flutter's canvases live in flutter-view's shadow root: walk every root.
  const deep = (selector) => {
    const found = [];
    const walk = (root) => {
      found.push(...root.querySelectorAll(selector));
      root.querySelectorAll('*').forEach((el) => {
        if (el.shadowRoot) walk(el.shadowRoot);
      });
    };
    walk(document);
    return found;
  };
  const alive = P.contexts.filter((c) => c.ref.deref() !== undefined);
  const webgl = (c) => /webgl/.test(c.type);
  const inDom = (el) => !!el && el.isConnected;
  const canvases = deep('canvas');
  const inFlutter = canvases.filter((c) => !c.closest('.gm-style') && (c.getRootNode() instanceof ShadowRoot || c.closest('flt-canvas-container, flt-scene-host, flutter-view')));
  const inMaps = canvases.filter((c) => c.closest('.gm-style'));
  const mapDivsAlive = P.maps.filter((m) => m.div.deref() !== undefined);
  const mem = performance.memory
    ? { usedJSHeap: performance.memory.usedJSHeapSize, totalJSHeap: performance.memory.totalJSHeapSize }
    : null;
  return {
    owner: window.moveraMapOwner || '',
    generation: window.moveraMapGeneration || 0,
    surface: window.moveraRestoreSurface || '',
    canvasesInDom: canvases.length,
    flutterCanvases: inFlutter.length,
    mapCanvases: inMaps.length,
    otherCanvases: canvases.length - inFlutter.length - inMaps.length,
    platformViews: deep('flt-platform-view').length,
    platformViewTypes: deep('flt-platform-view').map((v) => (v.firstElementChild && v.firstElementChild.id) || v.getAttribute('slot') || '?').map((id) => id.replace(/_\d+$/, '')).reduce((acc, id) => ((acc[id] = (acc[id] || 0) + 1), acc), {}),
    gmStyleRoots: deep('.gm-style').length,
    mapDivsInDom: deep('[id^="plugins.flutter.io/google_maps_"]').length,
    contextTypes: alive.reduce((acc, c) => { const k = `${c.creator}:${c.type}${inDom(c.ref.deref()) ? '' : ':detached'}${c.lost ? ':lost' : ''}`; acc[k] = (acc[k] || 0) + 1; return acc; }, {}),
    flutterWebglAlive: alive.filter((c) => webgl(c) && c.creator === 'flutter').length,
    flutterWebglHeld: alive.filter((c) => webgl(c) && c.creator === 'flutter' && !c.lost).length,
    mapsWebglAlive: alive.filter((c) => webgl(c) && c.creator === 'maps').length,
    mapsWebglHeld: alive.filter((c) => webgl(c) && c.creator === 'maps' && !c.lost).length,
    gestureStates: (() => { try { let n = 0; for (let i = 0; i < 200; i++) if (window.riderMapCamera && window.riderMapCamera.has(i)) n++; return n; } catch (_) { return -1; } })(),
    layerStats: (() => { try { return window.riderMapCamera && window.riderMapCamera.stats ? window.riderMapCamera.stats() : null; } catch (_) { return null; } })(),
    contextsCreated: P.contexts.length,
    webglCreated: P.contexts.filter(webgl).length,
    contextsAlive: alive.length,
    webglAlive: alive.filter(webgl).length,
    webglAliveDetached: alive.filter((c) => webgl(c) && !inDom(c.ref.deref())).length,
    webglAliveNotLost: alive.filter((c) => webgl(c) && !c.lost).length,
    contextsLost: P.lostContexts,
    contextsRestored: P.restoredContexts,
    mapsCreated: P.maps.length,
    mapsAlive: mapDivsAlive.length,
    mapsAliveDetached: mapDivsAlive.filter((m) => !inDom(m.div.deref())).length,
    mapObjectsAlive: P.maps.filter((m) => m.map.deref() !== undefined).length,
    activeIntervals: P.intervals.size,
    rafPending: P.rafPending.size,
    pageErrors: P.pageErrors.length,
    mem,
  };
};

const browser = await chromium.launch({
  headless: !headed,
  args: [
    '--use-angle=swiftshader',
    '--enable-unsafe-swiftshader',
    '--ignore-gpu-blocklist',
    '--enable-precise-memory-info',
    '--js-flags=--expose-gc',
    '--disable-dev-shm-usage',
  ],
});
const context = await browser.newContext({
  viewport: { width: 390, height: 844 },
  deviceScaleFactor: 2,
  isMobile: true,
  hasTouch: true,
  locale: 'en-US',
  geolocation: { latitude: 59.33258, longitude: 18.0649 },
  permissions: ['geolocation'],
  ignoreHTTPSErrors: true,
});
await context.addInitScript(instrument);
await context.addInitScript((raster) => { window.__probeRaster = raster; }, raster);
const page = await context.newPage();
const consoleErrors = [];
const pageErrors = [];
page.on('pageerror', (e) => pageErrors.push(`${String(e)}\n${String(e.stack || '').split('\n').slice(0, 5).join('\n')}`));
page.on('console', (m) => {
  if (m.type() === 'error' || m.type() === 'warning') consoleErrors.push(`${m.type()}: ${m.text().slice(0, 300)}`);
});
const cdp = await context.newCDPSession(page);
await cdp.send('Performance.enable');
await cdp.send('HeapProfiler.enable');

const rows = [];
let step = 0;
// Without an API key Google shows a modal over every map: close it.
async function dismissMapsDialog() {
  await page.evaluate(() => document.querySelectorAll('.dismissButton').forEach((b) => b.click()));
}

// Frame callbacks since `since` (performance.now() in the page): count, p95
// and worst main-thread time, and how many ran over 16 ms and 32 ms.
async function frameStats(since) {
  return page.evaluate((t0) => {
    const d = window.__probe.frames.filter(([t]) => t >= t0).map(([, ms]) => ms).sort((a, b) => a - b);
    const q = (p) => (d.length ? +d[Math.min(d.length - 1, Math.floor(p * d.length))].toFixed(1) : 0);
    return { frames: d.length, p50: q(0.5), p95: q(0.95), max: d.length ? +d[d.length - 1].toFixed(1) : 0, over16: d.filter((x) => x > 16).length, over32: d.filter((x) => x > 32).length };
  }, since);
}

async function snapshot(label, cycle) {
  const settleStart = await page.evaluate(() => performance.now());
  await page.waitForTimeout(settle);
  const frameCost = await frameStats(settleStart);
  await dismissMapsDialog();
  await cdp.send('HeapProfiler.collectGarbage');
  await page.evaluate(() => window.gc && window.gc());
  await page.waitForTimeout(300);
  await cdp.send('HeapProfiler.collectGarbage');
  const state = await page.evaluate(readState);
  const metrics = (await cdp.send('Performance.getMetrics')).metrics;
  const m = Object.fromEntries(metrics.map((x) => [x.name, x.value]));
  const row = {
    step: step++,
    cycle,
    label,
    ...state,
    jsHeapUsedMB: +(m.JSHeapUsedSize / 1048576).toFixed(1),
    jsHeapTotalMB: +(m.JSHeapTotalSize / 1048576).toFixed(1),
    nodes: m.Nodes,
    listeners: m.JSEventListeners,
    documents: m.Documents,
    frames: m.Frames,
    layoutObjects: m.LayoutObjects,
    // Frames drawn while the screen sat still for --settle ms (no input).
    frameCost,
  };
  rows.push(row);
  const short = `${String(row.step).padStart(2)} c${cycle} ${label.padEnd(12)} owner=${row.owner.padEnd(11)} ` +
    `ctx=${JSON.stringify(row.contextTypes)} pv=${JSON.stringify(row.platformViewTypes)} layer=${JSON.stringify(row.layerStats)}\n     ` +
    `flutter webgl alive/held=${row.flutterWebglAlive}/${row.flutterWebglHeld} maps webgl alive/held=${row.mapsWebglAlive}/${row.mapsWebglHeld} ` +
    `canvas=${row.canvasesInDom}(fl ${row.flutterCanvases}/gm ${row.mapCanvases}) pv=${row.platformViews} gm=${row.gmStyleRoots} ` +
    `webgl created/alive/detached/lost=${row.webglCreated}/${row.webglAlive}/${row.webglAliveDetached}/${row.contextsLost} ` +
    `maps created/alive/detached=${row.mapsCreated}/${row.mapsAlive}/${row.mapsAliveDetached} ` +
    `heap=${row.jsHeapUsedMB}MB nodes=${row.nodes} listeners=${row.listeners} intervals=${row.activeIntervals} raf=${row.rafPending}\n     ` +
    `idle frames=${frameCost.frames} p95=${frameCost.p95}ms max=${frameCost.max}ms >32ms=${frameCost.over32}`;
  console.log(short);
  if (shots) await page.screenshot({ path: path.join(shots, `${String(row.step).padStart(2, '0')}-c${cycle}-${label}.png`) });
  return row;
}

async function waitOwner(expected, timeout = 20000) {
  try {
    await page.waitForFunction((o) => window.moveraMapOwner === o, expected, { timeout });
    return true;
  } catch (_) {
    const actual = await page.evaluate(() => window.moveraMapOwner || '');
    console.log(`  ! expected map owner ${expected}, got ${actual || 'none'}`);
    return false;
  }
}

async function tap(x, y) {
  await page.touchscreen.tap(x, y);
}

async function typeDestination(text) {
  let inputs = page.locator('input:not([type="submit"]):not([type="hidden"]):visible, textarea:visible');
  let count = await inputs.count().catch(() => 0);
  if (!count) {
    await tap(185, 274);
    await page.waitForTimeout(500);
    inputs = page.locator('input:not([type="submit"]):not([type="hidden"]):visible, textarea:visible');
    count = await inputs.count();
  }
  if (!count) throw new Error('destination input missing');
  await inputs.last().pressSequentially(text, { delay: 10 });
}

// The screens' controls, by position on a 390x844 viewport (there is no
// semantics tree in a release build). Kept in one place to recalibrate.
const UI = {
  whereTo: [190, 708],
  destinationField: [200, 145],
  firstSuggestion: [200, 220],
  next: [195, 804],
  confirmPickup: [195, 797],
  selectRide: [195, 808],
  findingCancel: [36, 32],
  findingCancelConfirm: [195, 738],
  cancelWhySkip: [48, 526],
  completedDone: [195, 800],
};

// Release builds have no text in the DOM until Flutter's semantics tree is
// switched on (the hidden "Enable accessibility" placeholder). With it the
// screens' buttons can be found by their labels; without it, by position.
async function enableSemantics() {
  if (!useSemantics) return false;
  const placeholder = page.locator('flt-semantics-placeholder');
  if (!(await placeholder.count())) return false;
  await placeholder.first().click({ force: true }).catch(() => {});
  await page.waitForTimeout(1500);
  const nodes = await page.evaluate(() => document.querySelectorAll('flt-semantics').length);
  console.log(`semantics nodes: ${nodes}`);
  return nodes > 0;
}

// Taps a control by its label; falls back to the position.
async function press(label, fallback, { exact = true, timeout = 4000 } = {}) {
  const match = page.getByText(label, { exact });
  try {
    await match.last().waitFor({ state: 'visible', timeout });
    await match.last().click({ force: true });
    return 'text';
  } catch (_) {
    if (!fallback) throw new Error(`no control "${label}" and no fallback position`);
    await tap(...fallback);
    return 'tap';
  }
}

async function home() {
  await page.waitForFunction(() => window.moveraHomeBuilt === true, null, { timeout: 60000 });
  await waitOwner('home', 30000);
}

// Waits until the map owner is one of [expected]; returns it, or '' on timeout.
async function waitAnyOwner(expected, timeout = 30000) {
  try {
    await page.waitForFunction((list) => list.includes(window.moveraMapOwner || ''), expected, { timeout });
  } catch (_) {
    const actual = await page.evaluate(() => window.moveraMapOwner || '');
    console.log(`  ! expected map owner in ${expected.join('|')}, got ${actual || 'none'}`);
    return '';
  }
  return page.evaluate(() => window.moveraMapOwner || '');
}

// Home -> Plan your ride -> Select ride (categories) -> Set pickup
// ("Confirm and search") -> Finding. The order is read from the map owner,
// so a build that skips or reorders a step still gets measured.
async function book(cycle) {
  await snapshot('home', cycle);
  await press('Where to', UI.whereTo, { exact: false });
  await page.waitForTimeout(1200);
  await snapshot('address', cycle);
  await press('Where to?', UI.destinationField).catch(() => tap(...UI.destinationField));
  await page.waitForTimeout(400);
  await typeDestination('Stockholm Central Station');
  await page.waitForTimeout(1500);
  if (shots) await page.screenshot({ path: path.join(shots, `c${cycle}-typed.png`) });
  await press('Stockholm Central Station', UI.firstSuggestion, { exact: false, timeout: 6000 });
  let owner = await waitAnyOwner(['select_ride', 'pickup', 'finding'], 30000);
  for (let guard = 0; guard < 4 && owner !== 'finding'; guard++) {
    if (owner === 'select_ride') {
      await page.waitForTimeout(3000);
      await snapshot('select_ride', cycle);
      await press('Select Movera', UI.selectRide, { exact: false });
      owner = await waitAnyOwner(['pickup', 'finding'], 30000);
    } else if (owner === 'pickup') {
      await page.waitForTimeout(1500);
      await snapshot('pickup', cycle);
      await press('Confirm and search', UI.confirmPickup, { exact: false });
      owner = await waitAnyOwner(['finding', 'select_ride'], 30000);
    } else {
      break;
    }
  }
  if (owner !== 'finding') throw new Error(`cycle ${cycle}: never reached Finding (owner ${owner || 'none'})`);
  await snapshot('finding', cycle);
}

async function cancelSearch(cycle) {
  await dismissMapsDialog();
  await press('Cancel request', UI.findingCancel, { exact: false });
  await page.waitForTimeout(1200);
  if (shots) await page.screenshot({ path: path.join(shots, `c${cycle}-cancel-sheet.png`) });
  await press('Cancel request', UI.findingCancelConfirm, { exact: false });
  await page.waitForTimeout(1500);
  if (shots) await page.screenshot({ path: path.join(shots, `c${cycle}-after-cancel.png`) });
  // The ride is cancelled at once; the optional "Why are you cancelling?"
  // sheet stays over Finding until Skip. Home shows after that.
  await press('Skip', UI.cancelWhySkip);
  await waitOwner('home', 30000);
  await page.waitForTimeout(1500);
}

async function ridTrip(cycle) {
  const r = await page.evaluate(() => (typeof window.moveraAssignDriver === 'function' ? window.moveraAssignDriver() : 'missing'));
  if (r !== 'ok') console.log(`  ! moveraAssignDriver -> ${r}`);
  await waitOwner('waiting', 60000);
  await snapshot('waiting', cycle);
  // The demo driver walks to the pickup, then the trip runs: about a minute.
  await page.waitForFunction(() => window.moveraMapOwner !== 'waiting', null, { timeout: 180000 }).catch(() => {});
  await page.waitForTimeout(2000);
  await snapshot('completed', cycle);
  await press('Done', UI.completedDone);
  await waitOwner('home', 30000);
}

await page.goto(base, { waitUntil: 'load', timeout: 120000 });
await home();
await page.waitForTimeout(3000);
await enableSemantics();
await snapshot('boot', 0);

// --gps-minute: one minute on Home while the position moves every second
// (walking pace, ±3 m jitter), like a phone in the hand. Counts the frames the
// moving puck costs and the main-thread time (CDP TaskDuration) it takes.
let gpsMinute;
if (has('gps-minute')) {
  const before = Object.fromEntries((await cdp.send('Performance.getMetrics')).metrics.map((x) => [x.name, x.value]));
  const t0 = await page.evaluate(() => performance.now());
  for (let i = 0; i < 60; i++) {
    const j = (Math.sin(i * 1.7) * 3) / 111000;
    await context.setGeolocation({ latitude: 59.33258 + i * 0.00001 + j, longitude: 18.0649 + j, accuracy: 8 });
    await page.waitForTimeout(1000);
  }
  const after = Object.fromEntries((await cdp.send('Performance.getMetrics')).metrics.map((x) => [x.name, x.value]));
  gpsMinute = {
    ...(await frameStats(t0)),
    taskSeconds: +(after.TaskDuration - before.TaskDuration).toFixed(2),
    scriptSeconds: +(after.ScriptDuration - before.ScriptDuration).toFixed(2),
  };
  console.log(`gps minute on Home: ${JSON.stringify(gpsMinute)}`);
}

for (let cycle = 1; cycle <= cycles; cycle++) {
  await book(cycle);
  if (mode === 'trip') await ridTrip(cycle);
  else await cancelSearch(cycle);
  await waitOwner('home', 30000);
}
await snapshot('home', cycles + 1);

const first = rows.find((r) => r.label === 'home' && r.cycle === 1);
const last = rows[rows.length - 1];
const summary = {
  cycles,
  mode,
  mapsCreated: last.mapsCreated,
  mapsAliveAfterGc: last.mapsAlive,
  mapsAliveDetached: last.mapsAliveDetached,
  webglCreated: last.webglCreated,
  webglAlive: last.webglAlive,
  webglAliveDetached: last.webglAliveDetached,
  contextsLost: last.contextsLost,
  heapFirstHomeMB: first?.jsHeapUsedMB,
  heapLastHomeMB: last.jsHeapUsedMB,
  nodesFirstHome: first?.nodes,
  nodesLastHome: last.nodes,
  listenersFirstHome: first?.listeners,
  listenersLastHome: last.listeners,
  gpsMinute,
  pageErrors: [...new Set(pageErrors)].slice(0, 10),
  ownerTimeline: await page.evaluate(() => window.__probe.owners),
  inPageErrors: await page.evaluate(() => [...new Set(window.__probe.pageErrors)].slice(0, 10)),
  consoleErrors: [...new Set(consoleErrors)].slice(0, 40),
};
console.log('SUMMARY ' + JSON.stringify(summary, null, 2));
fs.writeFileSync(out, JSON.stringify({ summary, rows }, null, 2));
await browser.close();
server.close();
