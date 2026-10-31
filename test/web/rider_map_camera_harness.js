// Runs web/rider_map_camera.js against a fake Google map and a manual
// frame clock (requestAnimationFrame at 60 fps), and prints, as JSON, how
// its app flights and follow glides move the camera.
//
// node rider_map_camera_harness.js <rider_map_camera.js>
'use strict';
const fs = require('fs');
const vm = require('vm');

const [layerPath] = process.argv.slice(2);

// --- Frame clock -----------------------------------------------------------
let now = 0, nextId = 1;
let callbacks = new Map();
const requestAnimationFrame = cb => { const id = nextId++; callbacks.set(id, cb); return id; };
const cancelAnimationFrame = id => { callbacks.delete(id); };
const frame = () => {
  now += 1000 / 60;
  const due = callbacks; callbacks = new Map();
  due.forEach(cb => cb(now));
};

// --- Fake Maps JavaScript --------------------------------------------------
class LatLng {
  constructor(lat, lng) { this._lat = lat; this._lng = lng; }
  lat() { return this._lat; }
  lng() { return this._lng; }
}
class FakeMap {
  constructor(div) {
    this.div = div; this.center = new LatLng(59.33, 18.06);
    this.zoom = 13; this.heading = 0; this.tilt = 0; this.moves = [];
  }
  getCenter() { return this.center; }
  getZoom() { return this.zoom; }
  getHeading() { return this.heading; }
  getTilt() { return this.tilt; }
  getRenderingType() { return 'VECTOR'; }
  moveCamera(c) {
    if (c.center) this.center = new LatLng(c.center.lat, c.center.lng);
    if (c.zoom != null) this.zoom = c.zoom;
    if (c.heading != null) this.heading = c.heading;
    if (c.tilt != null) this.tilt = c.tilt;
    this.moves.push(this.pose());
  }
  panTo(latLng) { this.moveCamera({center: {lat: latLng.lat(), lng: latLng.lng()}}); }
  pose() {
    return {lat: this.center.lat(), lng: this.center.lng(), zoom: this.zoom,
      heading: this.heading, tilt: this.tilt};
  }
}
class OverlayView {
  setMap() {}
  getProjection() { return null; }
}
const listeners = {};
const div = {
  id: 'plugins.flutter.io/google_maps_1', style: {}, isConnected: true,
  clientWidth: 390, clientHeight: 700,
  addEventListener: (type, listener) => { (listeners[type] ||= []).push(listener); },
};
const context = {
  google: {maps: {Map: FakeMap, OverlayView, Point: class {},
    RenderingType: {VECTOR: 'VECTOR', RASTER: 'RASTER'}}},
  requestAnimationFrame, cancelAnimationFrame,
  performance: {now: () => now},
  MutationObserver: class { observe() {} disconnect() {} },
  document: {body: {}},
  setInterval, clearInterval, Math, Number, Promise, Map, Set, Proxy, Reflect,
};
vm.createContext(context);
vm.runInContext(fs.readFileSync(layerPath, 'utf8'), context);
const layer = context.riderMapCamera;
const map = new context.google.maps.Map(div, {});

// --- Scenarios -------------------------------------------------------------
const place = pose => {
  map.center = new LatLng(pose.lat, pose.lng);
  map.zoom = pose.zoom; map.heading = pose.heading || 0; map.tilt = pose.tilt || 0;
  map.moves = [];
};
// Runs frames until [promise] settles (or [limit] frames); the frames it
// took and what it resolved with.
const settle = async (promise, limit = 600, each = () => {}) => {
  let result, done = false;
  promise.then(value => { result = value; done = true; });
  let frames = 0;
  while (!done && frames < limit) {
    frame(); frames++;
    each(frames);
    await null; await null;
  }
  return {frames, result, moves: map.moves.slice()};
};
const start = {lat: 59.33, lng: 18.06, zoom: 13, heading: 0, tilt: 0};
// 300 px east at zoom 13 (a degree of longitude is 2^13 * 256 / 360 px).
const east300 = {...start, lng: 18.06 + 300 / (256 * 2 ** 13 / 360)};
const steps = moves => {
  const out = [];
  for (let i = 1; i < moves.length; i++) out.push(moves[i].lng - moves[i - 1].lng);
  return out;
};

(async () => {
  const out = {};
  out.hasGlide = typeof layer.glide === 'function';

  place(start);
  let run = await settle(layer.flight(1, east300.lat, east300.lng, 15, 0, 0, 500));
  out.flight = {frames: run.frames, landed: run.result, last: run.moves.at(-1)};

  place(start);
  run = await settle(layer.glide(1, east300.lat, east300.lng, 13, 0, 0, 450));
  const glideSteps = steps(run.moves);
  out.glide = {frames: run.frames, landed: run.result, last: run.moves.at(-1),
    firstStep: glideSteps[0], peakStep: Math.max(...glideSteps),
    monotonic: glideSteps.every(s => s >= 0)};

  // A zoom-and-turn glide: zoom and heading arrive with the pan.
  place(start);
  run = await settle(layer.glide(1, east300.lat, east300.lng, 14, 40, 0, 450));
  out.zoomTurn = {frames: run.frames, landed: run.result, last: run.moves.at(-1)};

  // A newer goal mid-glide keeps the speed it has.
  place(start);
  const further = {...east300, lng: east300.lng + (east300.lng - start.lng)};
  let retargetAt = 0;
  run = await settle(layer.glide(1, east300.lat, east300.lng, 13, 0, 0, 450), 600, f => {
    if (f === 8) {
      retargetAt = map.moves.length;
      layer.retarget(1, further.lat, further.lng, 13, 0, 0);
    }
  });
  const retargetSteps = steps(run.moves);
  out.retarget = {frames: run.frames, landed: run.result, last: run.moves.at(-1),
    before: retargetSteps[retargetAt - 2], after: retargetSteps[retargetAt - 1],
    stalled: retargetSteps.some(s => s <= 0)};

  // A finger on the map stops the glide at once; cancel hands back the pose.
  place(start);
  const touched = layer.glide(1, east300.lat, east300.lng, 13, 0, 0, 450);
  let touchResult;
  touched.then(v => { touchResult = v; });
  frame(); frame(); frame();
  const movesBefore = map.moves.length;
  const touch = {touches: [{clientX: 10, clientY: 10}], preventDefault() {},
    stopImmediatePropagation() {}, target: {}};
  listeners.touchstart.forEach(l => l(touch));
  // Two fingers release the map to the rider at once.
  listeners.touchstart.forEach(l => l({...touch,
    touches: [{clientX: 10, clientY: 10}, {clientX: 60, clientY: 10}]}));
  for (let i = 0; i < 30; i++) frame();
  await null; await null;
  out.touch = {result: touchResult, movedAfter: map.moves.length - movesBefore};

  place(start);
  layer.glide(1, east300.lat, east300.lng, 13, 0, 0, 450);
  frame(); frame();
  const at = layer.cancelFlight(1);
  for (let i = 0; i < 30; i++) frame();
  out.cancel = {pose: at, live: map.pose(), movedAfter: map.moves.length - 2};

  // Owner 2026-10-31: the location button's zoom 13.8 is no limit for the
  // rider's fingers. A long two-finger pinch out from 13 goes past it.
  const fingers = (...xs) => xs.map(x => ({clientX: x, clientY: 300}));
  const fire = (type, touches) => listeners[type].forEach(l => l({type, touches,
    preventDefault() {}, stopImmediatePropagation() {}, target: {}}));
  place({...start, zoom: 13});
  fire('touchstart', fingers(170, 220));
  for (let i = 1; i <= 20; i++) fire('touchmove', fingers(170 - 8 * i, 220 + 8 * i));
  fire('touchend', []);
  out.pinch = {zoom: map.zoom};

  process.stdout.write(JSON.stringify(out));
})();
