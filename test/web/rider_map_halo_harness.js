// Runs web/rider_map_camera.js against a fake Google map and prints, as
// JSON, how the rider pin's accuracy halo (riderMapCamera.halo) is drawn
// and re-clamped as the map zooms.
//
// node rider_map_halo_harness.js <rider_map_camera.js>
'use strict';
const fs = require('fs');
const vm = require('vm');

const [layerPath] = process.argv.slice(2);

class LatLng {
  constructor(lat, lng) { this._lat = lat; this._lng = lng; }
  lat() { return this._lat; }
  lng() { return this._lng; }
}
class FakeMap {
  constructor(div) {
    this.div = div; this.center = new LatLng(59.2, 17.62);
    this.zoom = 15; this.heading = 0; this.tilt = 0; this.listeners = {};
  }
  getCenter() { return this.center; }
  getZoom() { return this.zoom; }
  getHeading() { return this.heading; }
  getTilt() { return this.tilt; }
  getRenderingType() { return 'VECTOR'; }
  addListener(type, fn) {
    (this.listeners[type] ||= []).push(fn);
    return {remove: () => {}};
  }
  // Like Maps JavaScript: zoom_changed fires inside the camera move.
  moveCamera(c) {
    if (c.center) this.center = new LatLng(c.center.lat, c.center.lng);
    if (c.zoom != null && c.zoom !== this.zoom) {
      this.zoom = c.zoom;
      (this.listeners.zoom_changed || []).forEach(fn => fn());
    }
  }
  panTo() {}
}
const circles = [];
class Circle {
  constructor(options) {
    this.options = {...options}; this.map = options.map || null;
    this.center = new LatLng(options.center.lat, options.center.lng);
    this.radius = options.radius; circles.push(this);
  }
  getMap() { return this.map; }
  setMap(map) { this.map = map; }
  getRadius() { return this.radius; }
  setRadius(r) { this.radius = r; }
  getCenter() { return this.center; }
  setCenter(c) { this.center = new LatLng(c.lat, c.lng); }
}
class OverlayView { setMap() {} getProjection() { return null; } }
const div = {
  id: 'plugins.flutter.io/google_maps_1', style: {}, isConnected: true,
  clientWidth: 393, clientHeight: 852, addEventListener: () => {},
};
const context = {
  google: {maps: {Map: FakeMap, Circle, OverlayView, Point: class {},
    event: {clearInstanceListeners: () => {}, trigger: () => {}},
    RenderingType: {VECTOR: 'VECTOR', RASTER: 'RASTER'}}},
  requestAnimationFrame: () => 0, cancelAnimationFrame: () => {},
  performance: {now: () => 0},
  MutationObserver: class { observe() {} disconnect() {} },
  document: {body: {}},
  setInterval, clearInterval, setTimeout, Math, Number, Promise, Map, Set,
  Proxy, Reflect,
};
vm.createContext(context);
vm.runInContext(fs.readFileSync(layerPath, 'utf8'), context);
const layer = context.riderMapCamera;
const map = new context.google.maps.Map(div, {});
const perPoint = zoom => 156543.03392 * Math.cos(59.2 * Math.PI / 180) / 2 ** zoom;
const screen = () => layer.haloOf(1).radius / perPoint(map.zoom);

const out = {hasHalo: typeof layer.halo === 'function'};
layer.halo(1, 59.2, 17.62, 40, 60, 110, '#7797A8', 0.35);
const halo = circles[0];
out.options = {fillColor: halo.options.fillColor, fillOpacity: halo.options.fillOpacity,
  strokeWeight: halo.options.strokeWeight, onMap: halo.getMap() === map};
out.circles = circles.length;
// Zoom 15 at 59.2 N: 40 m is about 15 pt, so the halo keeps 60 pt.
out.at15 = screen();
// Every zoom step of a pinch: re-clamped inside the same camera move.
out.pinch = [];
for (const z of [15.5, 16, 16.5, 17, 17.5, 18, 19]) {
  map.moveCamera({zoom: z});
  out.pinch.push({zoom: z, points: screen(), meters: layer.haloOf(1).radius});
}
map.moveCamera({zoom: 11});
out.at11 = screen();
// A new fix moves the same circle.
layer.halo(1, 59.21, 17.63, 40, 60, 110, '#7797A8', 0.35);
out.afterMove = {circles: circles.length, lat: layer.haloOf(1).lat};
// No accuracy known: the smallest halo.
layer.halo(1, 59.21, 17.63, null, 60, 110, '#7797A8', 0.35);
out.unknown = screen();
// Gone with a null centre.
layer.halo(1, null, null, null, 60, 110, '#7797A8', 0.35);
out.removed = {onMap: halo.getMap() !== null, haloOf: layer.haloOf(1)};
process.stdout.write(JSON.stringify(out));
