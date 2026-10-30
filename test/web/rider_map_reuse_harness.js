// Runs web/rider_map_camera.js against a fake Google map that, like the
// real one, fires 'tilesloaded' only once per Map, then mounts a second
// plugin map after the first was released, and prints, as JSON, whether
// the reused map would be reported ready to google_maps_flutter_web (its
// onMapCreated waits for the first 'tilesloaded') and where its camera is.
//
// node rider_map_reuse_harness.js <rider_map_camera.js>
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
class FakeMap {
  constructor(div, options = {}) {
    this.div = div; this.zoom = options.zoom ?? 3; this.heading = 0; this.tilt = 0;
    this.center = options.center
      ? new LatLng(options.center.lat, options.center.lng) : new LatLng(0, 0);
    // Tiles load once per Map: Google fires 'tilesloaded' a single time.
    setTimeout(() => event.trigger(this, 'tilesloaded'), 5);
  }
  setOptions() {}
  setCenter(c) {
    this.centerSets = (this.centerSets || 0) + 1;
    this.center = typeof c.lat === 'function'
      ? new LatLng(c.lat(), c.lng()) : new LatLng(c.lat, c.lng);
  }
  setZoom(z) { this.zoom = z; }
  setHeading(h) { this.heading = h; }
  setTilt(t) { this.tilt = t; }
  getCenter() { return this.center; }
  getZoom() { return this.zoom; }
  getHeading() { return this.heading; }
  getTilt() { return this.tilt; }
  getRenderingType() { return 'VECTOR'; }
  moveCamera(c) {
    if (c.center) this.center = new LatLng(c.center.lat, c.center.lng);
    if (c.zoom != null) this.zoom = c.zoom;
  }
  panTo(latLng) { this.moveCamera({center: {lat: latLng.lat(), lng: latLng.lng()}}); }
}
class OverlayView { setMap() {} getProjection() { return null; } }
const element = id => ({
  id, style: {}, isConnected: true, clientWidth: 390, clientHeight: 700,
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
  HTMLCanvasElement: class {},
  document: {body: {}}, console,
  setTimeout, clearTimeout, setInterval, clearInterval,
  Math, Number, Promise, Map, Set, Proxy, Reflect,
};
vm.createContext(context);
vm.runInContext(fs.readFileSync(layerPath, 'utf8'), context);
const layer = context.riderMapCamera;
const GMap = context.google.maps.Map;

// How google_maps_flutter_web 0.5.14 builds a map: construct, then listen
// for the first 'tilesloaded' to report it created.
const mount = (id, options) => {
  const map = new GMap(element(`plugins.flutter.io/google_maps_${id}`), options);
  let ready = false;
  event.addListener(map, 'tilesloaded', () => { ready = true; });
  return {map, isReady: () => ready};
};

(async () => {
  const out = {};
  // Home: a zoomed-out view.
  const first = mount(1, {center: {lat: 20, lng: 0}, zoom: 3});
  await sleep(30);
  out.firstReady = first.isReady();
  first.map.div.isConnected = false;
  layer.release(1);
  await sleep(300);
  out.pooled = layer.stats().pooled;
  // Set pickup mounts its own map at the rider's position.
  const second = mount(2, {center: {lat: 59.33, lng: 18.06}, zoom: 16});
  await sleep(30);
  out.reused = second.map === first.map;
  out.secondReady = second.isReady();
  out.camera = {lat: second.map.getCenter().lat(), lng: second.map.getCenter().lng(),
    zoom: second.map.getZoom()};
  // Owner decision (rider map): the map's box grew; the layer makes Google
  // measure its element again ('resize') and redraw on the same camera.
  let resized = 0;
  event.addListener(second.map, 'resize', () => { resized += 1; });
  const sets = second.map.centerSets || 0;
  layer.redraw(2);
  layer.redraw(99); // an unknown map: nothing happens
  out.redraw = {resized, centerSet: (second.map.centerSets || 0) - sets,
    lat: second.map.getCenter().lat(), lng: second.map.getCenter().lng()};
  process.stdout.write(JSON.stringify(out));
  process.exit(0);
})();
