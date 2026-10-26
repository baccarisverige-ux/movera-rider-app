// Select ride sheet drag probe: measures what one drag of the categories
// sheet costs in a built rider web app, in Chromium.
//
// Why: on the installed iPhone web app the owner found the sheet on the
// categories screen slow to slide. The sheet moves over a Google map, which
// on the web is a platform view (an HTML element composited between
// Flutter's canvases), so every frame of the drag the engine re-rasterizes
// the canvas above the map and updates the DOM around it. This script drives
// Home -> Plan your ride -> Select ride, then drags the sheet up and down
// N times by its title and records, over the drag window:
//   - requestAnimationFrame deltas (p50 / p95 / max, frames over 16.7 ms
//     and over 32 ms),
//   - Flutter's own frame timings, build (Dart widgets, layout, paint
//     recording) and raster (CanvasKit) per frame, through the QA hook
//     window.moveraFrameTimings (a --dart-define=MOVERA_QA=true build),
//   - the browser's layout and style recalculation counts and durations
//     and its script time (CDP Performance.getMetrics),
//   - the Flutter canvases, platform views and Google map roots in the DOM
//     while the sheet moves,
//   - optionally (--trace) a CDP trace, summed by event name.
//
// Usage (from the repository root, after `flutter build web` with
// --dart-define=MOVERA_QA=true):
//   node tool/select_ride_sheet_probe.mjs [--dir build/web] [--drags 10]
//        [--multi-surface] [--raster] [--no-maps] [--blank-map] [--trace]
//        [--grip title|list] [--idle-ms 2000] [--maps-key KEY]
//        [--out probe.json] [--shots DIR] [--headed]
//
// --multi-surface forces the rasterizer Flutter uses on Safari (one WebGL
// context per display canvas). --raster strips the cloud Map ID (no Maps
// key in the sandbox: vector maps fall back to raster anyway). --no-maps
// leaves the Maps script out, so the screen shows the app's no-map surface
// and no platform view: the cost of the sheet alone. --blank-map keeps the
// map platform view but hides Google's own DOM (visibility: hidden), which
// separates the engine's compositing around the view from Google's tiles.
// Chromium runs with SwiftShader, so the times are larger than a phone's;
// read the numbers against each other, not as the iPhone's.
import { createRequire } from 'node:module';
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';

const require = createRequire(import.meta.url);
const { chromium } = require('playwright');

const args = process.argv.slice(2);
const opt = (name, fallback) => {
  const i = args.indexOf(`--${name}`);
  return i === -1 ? fallback : args[i + 1];
};
const has = (name) => args.includes(`--${name}`);

const dir = path.resolve(opt('dir', 'build/web'));
const drags = Number(opt('drags', '10'));
const mapsKey = opt('maps-key', process.env.MAPS_WEB_API_KEY || '');
const out = opt('out', 'select-ride-sheet-probe.json');
const shots = opt('shots', '');
const headed = has('headed');
const multiSurface = has('multi-surface');
const raster = has('raster');
const noMaps = has('no-maps');
const blankMap = has('blank-map');
const trace = has('trace');
// Where the finger goes: 'title' drags the fixed header (the app moves the
// sheet by hand), 'list' drags the rides (the draggable sheet's own scroll).
const grip = opt('grip', 'title');
// The rest before the drags (to see what the screen does on its own).
const idleMs = Number(opt('idle-ms', '2000'));

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
  '.webp': 'image/webp',
};

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
    if (!noMaps && !html.includes('maps.googleapis.com/maps/api/js')) {
      html = html.replace(
        bootstrap,
        `<script src="https://maps.googleapis.com/maps/api/js?key=${mapsKey}" async defer></script>\n${bootstrap}`,
      );
    }
    body = Buffer.from(html, 'utf8');
  } else if (path.basename(file) === 'flutter_bootstrap.js') {
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

// Installed before any page script: the frame recorder and the Maps
// constructor wrapper (--raster).
const instrument = () => {
  const P = (window.__sheet = { frames: [], samples: [], running: false, raf: 0, errors: [] });
  try {
    localStorage.setItem('flutter.movera_app_language', '"en"');
  } catch (_) {}
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
  P.count = () => {
    const canvases = deep('canvas');
    const flutter = canvases.filter((c) => !c.closest('.gm-style'));
    return {
      flutterCanvases: flutter.length,
      mapCanvases: canvases.length - flutter.length,
      platformViews: deep('flt-platform-view').length,
      gmStyleRoots: deep('.gm-style').length,
    };
  };
  P.start = () => {
    P.frames = [];
    P.samples = [];
    P.running = true;
    let last = performance.now();
    let n = 0;
    const tick = (t) => {
      if (!P.running) return;
      P.frames.push(t - last);
      last = t;
      if (n++ % 12 === 0) P.samples.push(P.count());
      P.raf = requestAnimationFrame(tick);
    };
    P.raf = requestAnimationFrame((t) => {
      last = t;
      P.raf = requestAnimationFrame(tick);
    });
  };
  P.stop = () => {
    P.running = false;
    cancelAnimationFrame(P.raf);
    return { frames: P.frames, samples: P.samples };
  };
  window.addEventListener('error', (e) => P.errors.push(String(e.message)));
  const wrap = () => {
    const g = globalThis.google;
    if (!g || !g.maps || typeof g.maps.Map !== 'function' || g.maps.Map.__probeWrapped) return false;
    const Native = g.maps.Map;
    const Wrapped = new Proxy(Native, {
      construct(target, a) {
        if (window.__probeRaster && a[1] && 'mapId' in a[1]) {
          a = [a[0], { ...a[1], mapId: undefined }, ...a.slice(2)];
        }
        return Reflect.construct(target, a);
      },
    });
    Wrapped.__probeWrapped = true;
    g.maps.Map = Wrapped;
    return true;
  };
  const poll = setInterval(() => {
    if (wrap()) clearInterval(poll);
  }, 20);
};

const browser = await chromium.launch({
  headless: !headed,
  args: [
    '--use-angle=swiftshader',
    '--enable-unsafe-swiftshader',
    '--ignore-gpu-blocklist',
    '--enable-precise-memory-info',
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
await context.addInitScript((r) => { window.__probeRaster = r; }, raster);
const page = await context.newPage();
const consoleErrors = [];
page.on('pageerror', (e) => consoleErrors.push(`pageerror: ${String(e).slice(0, 300)}`));
page.on('console', (m) => {
  if (m.type() === 'error') consoleErrors.push(`${m.type()}: ${m.text().slice(0, 300)}`);
});
const cdp = await context.newCDPSession(page);
await cdp.send('Performance.enable');

const tap = (x, y) => page.touchscreen.tap(x, y);

async function dismissMapsDialog() {
  await page.evaluate(() => document.querySelectorAll('.dismissButton').forEach((b) => b.click()));
}

// The screens' controls, by position on a 390x844 viewport (no semantics
// tree: switching it on would add its own per-frame DOM work to the
// measurement).
const UI = {
  whereTo: [190, 708],
  destinationField: [200, 145],
  firstSuggestion: [200, 220],
};

async function typeDestination(text) {
  let inputs = page.locator('input:not([type="submit"]):not([type="hidden"]):visible, textarea:visible');
  let count = await inputs.count().catch(() => 0);
  if (!count) {
    await tap(...UI.destinationField);
    await page.waitForTimeout(500);
    inputs = page.locator('input:not([type="submit"]):not([type="hidden"]):visible, textarea:visible');
    count = await inputs.count();
  }
  if (!count) throw new Error('destination input missing');
  await inputs.last().pressSequentially(text, { delay: 10 });
}

async function waitOwner(expected, timeout = 30000) {
  await page.waitForFunction((o) => window.moveraMapOwner === o, expected, { timeout });
}

// Select ride's sheet geometry on this viewport (select_ride.dart): the
// header is 65 px (handle 22, title 42, line 1), the low stop 289 px, the
// middle stop 449 px, the full stop 792 px (screen height minus the 52 px
// strip of map above the sheet; no status bar in Chromium's emulation).
const H = 844;
const SHEET = { min: 289, mid: 449, max: 792 };
// Where the finger lands: the title row (inside the fixed header), or a
// point in the rides list.
const gripY = (sheetHeight) => H - sheetHeight + (grip === 'list' ? 120 : 43);

// One finger drag: touchStart, moves 16 ms apart, touchEnd.
async function drag(x, fromY, toY, { steps = 28, stepMs = 16 } = {}) {
  await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x, y: fromY }] });
  for (let i = 1; i <= steps; i++) {
    const y = fromY + ((toY - fromY) * i) / steps;
    const started = Date.now();
    await cdp.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x, y }] });
    const left = stepMs - (Date.now() - started);
    if (left > 0) await page.waitForTimeout(left);
  }
  await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
}

const quantile = (list, q) => {
  if (!list.length) return 0;
  const sorted = [...list].sort((a, b) => a - b);
  return sorted[Math.min(sorted.length - 1, Math.floor(q * sorted.length))];
};
const stats = (list) => ({
  n: list.length,
  p50: +quantile(list, 0.5).toFixed(1),
  p90: +quantile(list, 0.9).toFixed(1),
  p95: +quantile(list, 0.95).toFixed(1),
  max: +(list.length ? Math.max(...list) : 0).toFixed(1),
  mean: +(list.length ? list.reduce((a, b) => a + b, 0) / list.length : 0).toFixed(1),
});

async function metrics() {
  const m = (await cdp.send('Performance.getMetrics')).metrics;
  return Object.fromEntries(m.map((x) => [x.name, x.value]));
}

const flutterTimings = () => page.evaluate(() => {
  if (typeof window.moveraFrameTimings !== 'function') return null;
  return JSON.parse(window.moveraFrameTimings());
});

let traceEvents = [];
cdp.on('Tracing.dataCollected', (e) => { traceEvents.push(...e.value); });

// Measures a window: start the frame recorder, run [body], stop, and
// report the rAF deltas, Flutter's build/raster, the browser's metrics
// and the DOM counts.
async function measure(label, body) {
  await flutterTimings();
  const before = await metrics();
  if (trace) {
    traceEvents = [];
    await cdp.send('Tracing.start', {
      categories: 'devtools.timeline,disabled-by-default-devtools.timeline,disabled-by-default-devtools.timeline.frame,v8.execute',
      options: 'sampling-frequency=10000',
      transferMode: 'ReportEvents',
    });
  }
  const t0 = Date.now();
  await page.evaluate(() => window.__sheet.start());
  await body();
  const { frames, samples } = await page.evaluate(() => window.__sheet.stop());
  const wallMs = Date.now() - t0;
  let traceSummary = null;
  if (trace) {
    const done = new Promise((resolve) => cdp.once('Tracing.tracingComplete', resolve));
    await cdp.send('Tracing.end');
    await done;
    const byName = {};
    for (const e of traceEvents) {
      if (e.ph !== 'X' || !e.dur) continue;
      const name = e.name;
      byName[name] = byName[name] || { count: 0, ms: 0 };
      byName[name].count += 1;
      byName[name].ms += e.dur / 1000;
    }
    traceSummary = Object.fromEntries(
      Object.entries(byName)
        .filter(([name]) => /^(Layout|UpdateLayoutTree|Paint|PrePaint|Layerize|Commit|FunctionCall|RunTask|TimerFire|FireAnimationFrame|HitTest|GPUTask|RasterTask|EventDispatch|ScheduleStyleRecalculation|UpdateLayer|CompositeLayers|DrawFrame|BeginMainThreadFrame)$/.test(name))
        .sort((a, b) => b[1].ms - a[1].ms)
        .map(([k, v]) => [k, { count: v.count, ms: +v.ms.toFixed(1) }]),
    );
  }
  const after = await metrics();
  const flutter = await flutterTimings();
  const d = (k) => +(after[k] - before[k]).toFixed(3);
  const row = {
    label,
    wallMs,
    raf: {
      ...stats(frames),
      over16: frames.filter((f) => f > 16.7).length,
      over32: frames.filter((f) => f > 32).length,
      over50: frames.filter((f) => f > 50).length,
    },
    flutter: flutter && {
      frames: flutter.frames,
      build: stats(flutter.build),
      raster: stats(flutter.raster),
      total: stats(flutter.total),
      buildOver16: flutter.build.filter((f) => f > 16.7).length,
      totalOver32: flutter.total.filter((f) => f > 32).length,
    },
    browser: {
      layoutCount: d('LayoutCount'),
      recalcStyleCount: d('RecalcStyleCount'),
      layoutMs: +(d('LayoutDuration') * 1000).toFixed(1),
      recalcStyleMs: +(d('RecalcStyleDuration') * 1000).toFixed(1),
      scriptMs: +(d('ScriptDuration') * 1000).toFixed(1),
      taskMs: +(d('TaskDuration') * 1000).toFixed(1),
      nodes: after.Nodes,
      listeners: after.JSEventListeners,
      jsHeapMB: +(after.JSHeapUsedSize / 1048576).toFixed(1),
    },
    dom: samples.length
      ? {
          flutterCanvases: [Math.min(...samples.map((s) => s.flutterCanvases)), Math.max(...samples.map((s) => s.flutterCanvases))],
          mapCanvases: [Math.min(...samples.map((s) => s.mapCanvases)), Math.max(...samples.map((s) => s.mapCanvases))],
          platformViews: [Math.min(...samples.map((s) => s.platformViews)), Math.max(...samples.map((s) => s.platformViews))],
          gmStyleRoots: [Math.min(...samples.map((s) => s.gmStyleRoots)), Math.max(...samples.map((s) => s.gmStyleRoots))],
        }
      : null,
    trace: traceSummary,
  };
  const f = row.flutter;
  console.log(
    `${label.padEnd(14)} ${wallMs} ms  rAF n=${row.raf.n} p50=${row.raf.p50} p95=${row.raf.p95} max=${row.raf.max} >16=${row.raf.over16} >32=${row.raf.over32}` +
      (f ? `  | flutter n=${f.frames} build p50/p95=${f.build.p50}/${f.build.p95} raster p50/p95=${f.raster.p50}/${f.raster.p95} total p50/p95=${f.total.p50}/${f.total.p95} >32=${f.totalOver32}` : '') +
      `  | layouts=${row.browser.layoutCount} (${row.browser.layoutMs} ms) styles=${row.browser.recalcStyleCount} script=${row.browser.scriptMs} ms` +
      (row.dom ? `  | canvases=${row.dom.flutterCanvases.join('-')} pv=${row.dom.platformViews.join('-')} gm=${row.dom.gmStyleRoots.join('-')}` : ''),
  );
  if (traceSummary) console.log('   trace: ' + JSON.stringify(traceSummary));
  return row;
}

await page.goto(base, { waitUntil: 'load', timeout: 120000 });
await page.waitForFunction(() => window.moveraHomeBuilt === true, null, { timeout: 60000 });
await waitOwner('home', 30000).catch(() => {});
await page.waitForTimeout(3000);
await tap(...UI.whereTo);
await page.waitForTimeout(1200);
await tap(...UI.destinationField);
await page.waitForTimeout(400);
await typeDestination('Stockholm Central Station');
await page.waitForTimeout(1500);
await tap(...UI.firstSuggestion);
// Without the Maps script no map owner is ever reported: give the screen
// the time it takes with one.
if (noMaps) await page.waitForTimeout(8000);
else await waitOwner('select_ride', 30000);
// Let the map come up, the camera fly and the quotes land.
await page.waitForTimeout(4000);
await dismissMapsDialog();
if (blankMap) {
  await page.evaluate(() => {
    document.querySelectorAll('.gm-style').forEach((el) => { el.style.visibility = 'hidden'; });
  });
  await page.waitForTimeout(500);
}
if (shots) await page.screenshot({ path: path.join(shots, '00-select-ride.png') });

const rows = [];
rows.push(await measure('idle', () => page.waitForTimeout(idleMs)));

const x = 195;
rows.push(
  await measure('drags', async () => {
    for (let i = 0; i < drags; i++) {
      // Up from the middle stop to the full stop, settle.
      await drag(x, gripY(SHEET.mid), gripY(SHEET.mid) - (SHEET.max - SHEET.mid));
      await page.waitForTimeout(700);
      if (shots && i === 0) await page.screenshot({ path: path.join(shots, '01-after-up.png') });
      // Down from the full stop back to the middle stop, settle.
      await drag(x, gripY(SHEET.max), gripY(SHEET.max) + (SHEET.max - SHEET.mid));
      await page.waitForTimeout(700);
      if (shots && i === 0) await page.screenshot({ path: path.join(shots, '02-after-down.png') });
    }
  }),
);
// The same without the settles: only frames with a finger on the sheet.
rows.push(
  await measure('finger-only', async () => {
    for (let i = 0; i < Math.max(1, Math.floor(drags / 2)); i++) {
      await drag(x, gripY(SHEET.mid), gripY(SHEET.mid) - (SHEET.max - SHEET.mid), { steps: 40 });
      await drag(x, gripY(SHEET.max), gripY(SHEET.max) + (SHEET.max - SHEET.mid), { steps: 40 });
    }
  }),
);
await page.waitForTimeout(1000);
if (shots) await page.screenshot({ path: path.join(shots, '03-end.png') });

const summary = {
  dir,
  drags,
  grip,
  multiSurface,
  raster,
  noMaps,
  blankMap,
  rows,
  consoleErrors: [...new Set(consoleErrors)].slice(0, 20),
  inPageErrors: await page.evaluate(() => [...new Set(window.__sheet.errors)].slice(0, 10)),
};
fs.writeFileSync(out, JSON.stringify(summary, null, 2));
console.log(`wrote ${out}`);
await browser.close();
server.close();
