// Runs web/rider_map_camera.js against a fake Google map that measures its
// element the way Maps JS 3.66 does (map.js): only when the hidden <iframe>
// it keeps in .gm-style fires 'load', or that frame's window fires
// 'resize'. The browser here never delivers those events after the first
// load (what leaves the grey band on the rider's iPhone), so only the
// rider layer's size watch can make Google measure again. Prints, as JSON,
// the sizes Google measured and the camera calls made along the way.
//
// node rider_map_size_watch_harness.js <rider_map_camera.js>
'use strict';
const fs = require('fs');
const vm = require('vm');

const [layerPath] = process.argv.slice(2);
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));

class LatLng {
  constructor(lat, lng) { this._lat = lat; this._lng = lng; }
  lat() { return this._lat; }
  lng() { return this._lng; }
}
const handlers = new WeakMap();
const on = (target, name) => {
  let byName = handlers.get(target);
  if (!byName) handlers.set(target, byName = {});
  return (byName[name] ||= []);
};
const event = {
  addListener(target, name, fn) { on(target, name).push(fn); return {remove() {}}; },
  trigger(target, name, ...args) { [...on(target, name)].forEach(fn => fn(...args)); },
  clearInstanceListeners(target) { handlers.delete(target); },
};

// The ResizeObservers the layer makes; the test reports sizes through them.
const observers = [];
class FakeResizeObserver {
  constructor(callback) {
    this.callback = callback; this.targets = new Set(); this.disconnected = false;
    observers.push(this);
  }
  observe(target) { this.targets.add(target); }
  unobserve(target) { this.targets.delete(target); }
  disconnect() { this.disconnected = true; this.targets.clear(); }
}
const report = (container, width, height) => {
  for (const observer of observers) {
    if (!observer.targets.has(container)) continue;
    observer.callback([{target: container, contentRect: {width, height}}], observer);
  }
};

const camera = {moves: 0, centers: 0, zooms: 0};
const measured = [];
class FakeMap {
  constructor(div, options = {}) {
    this.div = div; this.zoom = options.zoom ?? 15; this.heading = 0; this.tilt = 0;
    this.center = new LatLng(options.center?.lat ?? 0, options.center?.lng ?? 0);
    // Google's size frame: 'load' measures and starts listening to the
    // frame window's 'resize'; both read the element's current size.
    const frame = new EventTarget();
    frame.tagName = 'IFRAME';
    frame.getAttribute = name => (name === 'aria-hidden' ? 'true' : null);
    frame.contentWindow = new EventTarget();
    this.size = null;
    const measure = () => {
      const size = [div.clientWidth, div.clientHeight];
      measured.push(size[1]);
      this.size = size;
    };
    frame.addEventListener('load', () => {
      measure();
      frame.contentWindow.addEventListener('resize', measure);
    });
    this.frame = frame;
    const gm = {className: 'gm-style', children: [{tagName: 'DIV'}, frame]};
    div.querySelector = selector => (selector === '.gm-style' ? gm : null);
    // The browser loads the frame once, when the map is first shown.
    setTimeout(() => frame.dispatchEvent(new Event('load')), 1);
    setTimeout(() => event.trigger(this, 'tilesloaded'), 5);
  }
  setOptions() {}
  setCenter(c) {
    camera.centers += 1;
    this.center = typeof c.lat === 'function'
      ? new LatLng(c.lat(), c.lng()) : new LatLng(c.lat, c.lng);
  }
  setZoom(z) { camera.zooms += 1; this.zoom = z; }
  setHeading(h) { this.heading = h; }
  setTilt(t) { this.tilt = t; }
  getCenter() { return this.center; }
  getZoom() { return this.zoom; }
  getHeading() { return this.heading; }
  getTilt() { return this.tilt; }
  getRenderingType() { return 'VECTOR'; }
  moveCamera(c) {
    camera.moves += 1;
    if (c.center) this.center = new LatLng(c.center.lat, c.center.lng);
    if (c.zoom != null) this.zoom = c.zoom;
  }
  panTo(latLng) { this.moveCamera({center: {lat: latLng.lat(), lng: latLng.lng()}}); }
}
class OverlayView { setMap() {} getProjection() { return null; } }
const element = id => ({
  id, style: {}, isConnected: true, clientWidth: 390, clientHeight: 555,
  addEventListener() {}, appendChild() {}, remove() {},
  querySelectorAll: () => [], replaceChildren() {},
});
const context = {
  google: {maps: {Map: FakeMap, OverlayView, Point: class {}, event,
    RenderingType: {VECTOR: 'VECTOR', RASTER: 'RASTER'}}},
  requestAnimationFrame: cb => setTimeout(() => cb(Date.now()), 16),
  cancelAnimationFrame: id => clearTimeout(id),
  performance: {now: () => Date.now()},
  MutationObserver: class { observe() {} disconnect() {} },
  ResizeObserver: FakeResizeObserver,
  HTMLCanvasElement: class {},
  Event, EventTarget,
  document: {body: {}}, console,
  location: {search: ''}, sessionStorage: {getItem: () => null, setItem() {}, removeItem() {}},
  URLSearchParams,
  setTimeout, clearTimeout, setInterval, clearInterval,
  Math, Number, Promise, Map, Set, WeakSet, WeakMap, Proxy, Reflect,
};
vm.createContext(context);
vm.runInContext(fs.readFileSync(layerPath, 'utf8'), context);
const layer = context.riderMapCamera;
const GMap = context.google.maps.Map;

(async () => {
  const out = {};
  const div = element('plugins.flutter.io/google_maps_1');
  const map = new GMap(div, {center: {lat: 59.33, lng: 18.06}, zoom: 15});
  await sleep(30);
  out.watched = observers.some(o => o.targets.has(div));
  report(div, 390, 555); // the first observation, at the size Google has
  await sleep(40);
  out.firstSize = map.size && map.size[1];
  const cameraBefore = {...camera};
  const centerBefore = [map.getCenter().lat(), map.getCenter().lng(), map.getZoom()];
  const countBefore = measured.length;

  // The element grows (Home's box under a collapsing Safari toolbar, or a
  // pooled map moved into a taller box); the browser sends no frame event.
  div.clientHeight = 844;
  report(div, 390, 700);
  report(div, 390, 790);
  report(div, 390, 844); // three reports in one frame
  out.measuredSync = measured.length - countBefore; // nothing before the frame
  await sleep(40);
  out.grownSize = map.size && map.size[1];
  out.measuresForGrow = measured.length - countBefore;
  out.cameraCalls = {moves: camera.moves - cameraBefore.moves,
    centers: camera.centers - cameraBefore.centers, zooms: camera.zooms - cameraBefore.zooms};
  out.cameraKept = [map.getCenter().lat(), map.getCenter().lng(), map.getZoom()]
    .every((v, i) => v === centerBefore[i]);

  // Out of the page (pooled): 0 x 0 is not a size to draw.
  const beforeHidden = measured.length;
  div.clientHeight = 0;
  report(div, 0, 0);
  await sleep(40);
  out.measuresWhenHidden = measured.length - beforeHidden;

  // Back in a new box with a new frame window whose 'load' the browser
  // never delivered: Google has no 'resize' listener on it yet.
  map.frame.contentWindow = new EventTarget();
  div.clientHeight = 621;
  report(div, 390, 621);
  await sleep(40);
  out.newWindowSize = map.size && map.size[1];

  out.remeasured = layer.stats().remeasured;
  // A pooled map stays watched: its element is the one carried into the
  // next screen's box.
  div.isConnected = false;
  layer.release(1);
  await sleep(400);
  out.pooled = layer.stats().pooled;
  out.pooledStillWatched = observers.some(o => o.targets.has(div) && !o.disconnected);
  process.stdout.write(JSON.stringify(out));
  process.exit(0);
})();
