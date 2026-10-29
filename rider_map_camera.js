/* Rider Google Maps gesture layer for google_maps_flutter_web 0.5.14+2.
 * Same camera rules as the driver app (web/driver_map_camera.js there):
 * tilt follows zoom on every frame of a pinch or wheel zoom, tilt never
 * blocks zoom, and a programmatic camera step is instant (no panTo glide
 * between the frames of an ease). App flights and follow glides run here on
 * the browser's frame clock. Uses public Maps JS APIs only.
 */
(() => {
  'use strict';
  // Maps JavaScript may arrive after this file (async/defer). Install once
  // it is there; until then ready() is false and Dart skips every call.
  let sdk = null;
  const states = new Map();
  const clamp = (v, min, max) => Math.max(min, Math.min(max, v));
  const delta = (a, b) => ((b - a + 540) % 360) - 180;
  const touchPose = touches => {
    const a = touches[0], b = touches[1] || a;
    return {x: (a.clientX + b.clientX) / 2,
      y: (a.clientY + b.clientY) / 2, ay: a.clientY, by: b.clientY,
      span: Math.hypot(a.clientX - b.clientX, a.clientY - b.clientY),
      angle: Math.atan2(b.clientY - a.clientY, b.clientX - a.clientX) * 180 / Math.PI};
  };
  // Tilt follows zoom on every rider map (lib/core/maps/camera_tilt.dart
  // tiltForZoom; keep both in step, and in step with the driver app):
  // 0 deg at zoom 12, then proportional to zoom up to 67.5 deg at zoom
  // 15.5, under the SDKs' own per-zoom limit.
  const MAX_TILT = 67.5, FLAT_ZOOM = 12, FULL_TILT_ZOOM = 15.5;
  const sdkMaxTilt = zoom => zoom <= 10 ? 30 : zoom <= 14 ?
    30 + (zoom - 10) / 4 * 15 : zoom < 15.5 ?
    45 + (zoom - 14) / 1.5 * (MAX_TILT - 45) : MAX_TILT;
  const tiltForZoom = zoom => Number.isFinite(zoom) ?
    Math.min(MAX_TILT * clamp((zoom - FLAT_ZOOM) /
      (FULL_TILT_ZOOM - FLAT_ZOOM), 0, 1), sdkMaxTilt(zoom)) : 0;
  // A zoom step carries the tilt along the curve in the same camera move,
  // so the horizon rises as the rider zooms in and flattens as they zoom
  // out, frame by frame. A tilt set by hand is kept as an offset.
  // Rounding residue (1e-16) would keep a zoomed-out map a hair tilted.
  const tiltWithZoom = (tilt, from, to) => {
    const next = clamp(tilt + tiltForZoom(to) - tiltForZoom(from), 0, sdkMaxTilt(to));
    return next < 1e-9 ? 0 : next;
  };
  // The locate flight (lib/core/maps/map_camera_motion.dart flightEase;
  // keep both in step): three phases of equal length at an even speed, the
  // first and last at SLOW of the middle one, joined by short smoothstep
  // blends. It leaves at once and lands at the slow speed: no creep, no cut.
  const SLOW = .8, RISE_FROM = .25, RISE_TO = .40, FALL_FROM = .60, FALL_TO = .75;
  const bumpIntegral = x => {
    const w = RISE_TO - RISE_FROM;
    const rise = u => w * (u * u * u - u * u * u * u / 2);
    if (x <= RISE_FROM) return 0;
    if (x <= RISE_TO) return rise((x - RISE_FROM) / w);
    const full = rise(1);
    if (x <= FALL_FROM) return full + (x - RISE_TO);
    const plateau = full + (FALL_FROM - RISE_TO);
    if (x <= FALL_TO) { const u = (x - FALL_FROM) / w; return plateau + w * u - rise(u); }
    return plateau + w - full;
  };
  const flightEase = t => {
    const x = clamp(t, 0, 1);
    return (SLOW * x + (1 - SLOW) * bumpIntegral(x)) / (SLOW + (1 - SLOW) * .35);
  };
  // A ground step looks 2^zoom times bigger on screen: spread the pan so
  // its on-screen speed stays even while the camera zooms.
  const panShare = (zoomShare, dz) => Math.abs(dz) < 1e-3 ? zoomShare :
    (1 - 2 ** (-dz * clamp(zoomShare, 0, 1))) / (1 - 2 ** (-dz));
  const angleDelta = (from, to) => (to - from + 540) % 360 - 180;
  // The follow glide and its settle test (lib/core/maps/map_camera_motion.dart
  // _glideStep, _screenGap; keep both in step). A zoom of one level or a
  // turn of one radian moves the map's edge ~PX_PER_LEVEL px; a camera
  // within SETTLE_PX of its goal is there.
  const PX_PER_LEVEL = 300, SETTLE_PX = 1, GLIDE_TAU = .27, LANDING_PX = 6,
    ACCEL = 40000;
  const screenGap = (a, b, zoom) => {
    const world = 256 * 2 ** zoom;
    const lat = (a.lat + b.lat) / 2 * Math.PI / 180;
    const dx = (b.lng - a.lng) / 360 * world;
    const dy = (b.lat - a.lat) / 360 * world / Math.max(.01, Math.cos(lat));
    const turn = Math.abs(angleDelta(a.heading, b.heading)) * Math.PI / 180;
    const tilt = Math.abs(b.tilt - a.tilt) * Math.PI / 180;
    return Math.max(Math.hypot(dx, dy), Math.abs(b.zoom - a.zoom) * PX_PER_LEVEL,
      Math.max(turn, tilt) * PX_PER_LEVEL);
  };
  function pan(state, dx, dy) {
    const projection = state.overlay.getProjection();
    if (!projection) return;
    const center = projection.fromLatLngToContainerPixel(state.map.getCenter());
    if (!center) return;
    const target = projection.fromContainerPixelToLatLng(
      new sdk.Point(center.x - dx, center.y - dy));
    if (target) state.map.moveCamera({center: target});
  }
  function install(map, div, id) {
    // [div] is the element Google draws into for the life of this Map (its
    // container); a reused map is carried inside a later plugin element,
    // which state.div then names (see reuse below).
    const container = div;
    const state = {map, div, container, id, callbacks: new Set(), claim: false,
      gesturesEnabled: true, scroll: true, zoom: true, rotate: true, tilt: true,
      tiltFollowsZoom: true};
    const supports3D = () => map.getRenderingType?.() === sdk.RenderingType.VECTOR;
    state.supports3D = supports3D;
    const overlay = new sdk.OverlayView();
    overlay.onAdd = () => {};
    overlay.draw = () => {};
    overlay.onRemove = () => {};
    overlay.setMap(map);
    state.overlay = overlay;
    states.set(id, state);
    const nativeMove = map.moveCamera.bind(map);
    const nativePanTo = typeof map.panTo === 'function'
      ? map.panTo.bind(map)
      : latLng => nativeMove({center: latLng});
    // Flutter web applies a camera position with zoom/heading/tilt setters
    // and then panTo, which glides. One frame of an app ease claims the
    // next pan so the frame lands at once, exactly where it was asked.
    map.panTo = latLng => {
      if (!state.claim) { nativePanTo(latLng); return; }
      state.claim = false;
      nativeMove({center: latLng});
    };
    let previous, travel = 0, startedAt = 0, maxTouches = 0, lastTap = -Infinity;
    let lastTapPoint = null, lastTwoFingerPoint = null;
    let touchReleased = false;
    // A short but real pinch is not a two-finger tap: its fractional zoom
    // must not be followed by a full-level zoom-out on release.
    let multiTouchMoved = false;
    // A cancelled multi-touch stream must not be completed by a later
    // touchend as a stationary two-finger tap.
    let cancelledTouchSequence = false;
    let touchOnControl = false;
    let pointerOrigin = null;
    let pointerReleased = false;
    const nativeCameraControl = target => {
      if (!target?.closest) return false;
      if (target.closest('.gm-bundled-control, .gm-control-active')) return true;
      const button = target.closest('button[aria-label], button[title], [role="button"][aria-label]');
      if (!button) return false;
      const name = (button.getAttribute?.('aria-label') ||
          button.getAttribute?.('title') || '').toLowerCase();
      return /zoom|förstora|förminska/.test(name);
    };
    state.setGesturesEnabled = enabled => {
      state.gesturesEnabled = !!enabled;
      if (!enabled) {
        state.stopWheel?.();
        previous = null; pointerOrigin = null;
        touchReleased = false; pointerReleased = false;
        multiTouchMoved = false; cancelledTouchSequence = false;
        touchOnControl = false;
        lastTap = -Infinity; lastTapPoint = null;
      }
    };
    // App camera motion on the browser's frame clock: one moveCamera per
    // painted frame (a Dart timer stutters in Safari). A locate flight
    // closes, each frame, the share of the remaining way its ease covers;
    // a follow glide closes a speed-limited share of the gap left. Either
    // turns smoothly to a retargeted goal; tilt rides the zoom as in Dart's
    // _blend. One motion at a time: a newer one, a finger or a gesture
    // (release) ends it.
    let flight = null;
    const endFlight = landed => {
      const f = flight; if (!f) return;
      flight = null;
      if (f.frame) globalThis.cancelAnimationFrame?.(f.frame);
      f.resolve(landed);
    };
    const tiltFor = zoom => state.tiltFollowsZoom &&
      map.getRenderingType?.() !== sdk.RenderingType.RASTER ? tiltForZoom(zoom) : 0;
    // rider-j8-13: a cancelled motion stops mid-way; hand back where the
    // camera now is, so Dart's next glide starts from there.
    state.cancelFlight = () => {
      if (!flight) return null;
      endFlight(false);
      const c = map.getCenter();
      if (!c) return null;
      return {lat: c.lat(), lng: c.lng(), zoom: Number(map.getZoom()),
        heading: map.getHeading() || 0, tilt: map.getTilt() || 0};
    };
    state.retarget = to => { if (flight) flight.to = to; };
    const camera = () => {
      const c = map.getCenter(), zoom = Number(map.getZoom());
      if (!c || !Number.isFinite(zoom)) return null;
      return {lat: c.lat(), lng: c.lng(), zoom,
        heading: map.getHeading() || 0, tilt: map.getTilt() || 0};
    };
    const land = (f, goal) => {
      flight = null;
      nativeMove({center: {lat: goal.lat, lng: goal.lng}, zoom: goal.zoom,
        heading: goal.heading, tilt: clamp(goal.tilt, 0, sdkMaxTilt(goal.zoom))});
      f.resolve(true);
    };
    // [share] of the way from the camera [at] to [goal].
    const stepToward = (at, goal, share) => {
      const dz = goal.zoom - at.zoom, p = panShare(share, dz);
      const nextZoom = at.zoom + dz * share;
      const fromOffset = at.tilt - tiltFor(at.zoom), toOffset = goal.tilt - tiltFor(goal.zoom);
      const nextTilt = clamp(tiltFor(nextZoom) + fromOffset + (toOffset - fromOffset) * share,
        0, sdkMaxTilt(nextZoom));
      nativeMove({
        center: {lat: at.lat + (goal.lat - at.lat) * p, lng: at.lng + (goal.lng - at.lng) * p},
        zoom: nextZoom,
        heading: (at.heading + angleDelta(at.heading, goal.heading) * share + 360) % 360,
        tilt: nextTilt < 1e-9 ? 0 : nextTilt,
      });
    };
    const run = (f, frame) => {
      endFlight(false);
      flight = f;
      const tick = now => {
        if (flight !== f) return;
        frame(now);
        if (flight === f) f.frame = globalThis.requestAnimationFrame(tick);
      };
      f.frame = globalThis.requestAnimationFrame(tick);
    };
    state.flight = (to, ms) => new Promise(resolve => {
      const f = {to, resolve, started: null, prev: 0, frame: 0};
      run(f, now => {
        // The first frame already moves, like the Dart loop's frame 0.
        if (f.started == null) f.started = now - 16;
        const after = flightEase((now - f.started) / ms);
        const before = f.prev; f.prev = after;
        if (after >= 1) { land(f, f.to); return; }
        const at = camera();
        if (at) stepToward(at, f.to, (after - before) / (1 - before));
      });
    });
    // The follow glide (Dart's _glideStep; keep both in step): the speed
    // (px/s) goes towards the gap left plus LANDING_PX over the time
    // constant, gaining at most ACCEL, and lands exactly on the goal.
    state.glide = (to, ms) => new Promise(resolve => {
      const tau = Math.max(200, ms) * GLIDE_TAU / 1000;
      const f = {to, resolve, last: null, speed: 0, frame: 0};
      run(f, now => {
        // The first frame already moves; a stalled frame does not leap.
        const dt = f.last == null ? .016 : clamp((now - f.last) / 1000, .001, .064);
        f.last = now;
        const at = camera();
        if (!at) return;
        const goal = f.to;
        const gap = screenGap(at, goal, Math.max(at.zoom, goal.zoom));
        if (gap <= SETTLE_PX) { land(f, goal); return; }
        f.speed = Math.min((gap + LANDING_PX) / tau, f.speed + ACCEL * dt);
        const step = f.speed * dt;
        if (step >= gap - SETTLE_PX) { land(f, goal); return; }
        stepToward(at, goal, step / gap);
      });
    });
    // The rider moved the map by hand: Dart stops steering the camera.
    const release = () => {
      if (!state.gesturesEnabled) return;
      state.claim = false;
      endFlight(false);
      state.callbacks.forEach(callback => callback());
    };
    const releaseTouch = () => {
      if (!touchReleased) { touchReleased = true; release(); }
    };
    // moveCamera({zoom}) scales about the map center; a pinch scales about
    // the point between the fingers. Compensate in screen pixels so the
    // road under the fingers stays there.
    const zoomAt = (amount, x, y, camera = {}, gestureX = 0, gestureY = 0) => {
      const current = Number(map.getZoom());
      if (!Number.isFinite(current)) return;
      const next = state.zoom ? clamp(current + amount, 3, 21) : current;
      if (supports3D() && state.tiltFollowsZoom && !('tilt' in camera)) {
        camera = {...camera, tilt: tiltWithZoom(map.getTilt() || 0, current, next)};
      }
      map.moveCamera({...camera, zoom: next});
      let panX = state.scroll ? gestureX : 0, panY = state.scroll ? gestureY : 0;
      const width = container.clientWidth, height = container.clientHeight;
      if (width > 0 && height > 0 && Number.isFinite(x) &&
          Number.isFinite(y) && next !== current) {
        const rect = container.getBoundingClientRect?.() || {left: 0, top: 0};
        const scale = 2 ** (next - current);
        const localX = clamp(x - rect.left, 0, width);
        const localY = clamp(y - rect.top, 0, height);
        panX += (1 - scale) * (localX - width / 2);
        panY += (1 - scale) * (localY - height / 2);
      }
      if (panX || panY) pan(state, panX, panY);
    };
    container.style.touchAction = 'none';
    container.addEventListener('pointerdown', event => {
      if (!state.gesturesEnabled) return;
      if (nativeCameraControl(event.target)) { release(); pointerOrigin = null; return; }
      if (event.pointerType === 'touch') return;
      pointerOrigin = {x: event.clientX, y: event.clientY};
      pointerReleased = false;
    }, {capture: true});
    container.addEventListener('pointermove', event => {
      if (!state.gesturesEnabled || !pointerOrigin || pointerReleased) return;
      if (Math.hypot(event.clientX - pointerOrigin.x,
          event.clientY - pointerOrigin.y) >= 6) {
        pointerReleased = true;
        release();
      }
    }, {capture: true});
    const clearPointer = () => { pointerOrigin = null; pointerReleased = false; };
    container.addEventListener('pointerup', clearPointer, {capture: true});
    container.addEventListener('pointercancel', clearPointer, {capture: true});
    container.addEventListener('dblclick', release, {capture: true});
    // Wheel / trackpad zoom on a vector map: Google's wheel animation would
    // zoom with a fixed tilt, so this layer glides toward the wheel's goal,
    // about the cursor, with the tilt bound to the zoom on every frame.
    let wheelGoal = null, wheelPoint = null, wheelFrame = 0, wheelSet = null;
    const stopWheel = () => {
      if (wheelFrame) globalThis.cancelAnimationFrame?.(wheelFrame);
      wheelFrame = 0; wheelGoal = null; wheelSet = null;
    };
    state.stopWheel = stopWheel;
    const wheelTick = () => {
      wheelFrame = 0;
      const current = Number(map.getZoom());
      // Someone else moved the camera (recenter), or Maps capped the zoom.
      if (wheelGoal == null || !Number.isFinite(current) ||
          (wheelSet != null && Math.abs(current - wheelSet) > .001)) {
        stopWheel();
        return;
      }
      const left = wheelGoal - current;
      const step = Math.abs(left) < .01 ? left : left * .35;
      zoomAt(step, wheelPoint.x, wheelPoint.y);
      wheelSet = Number(map.getZoom());
      if (Math.abs(left) < .01) { stopWheel(); return; }
      wheelFrame = globalThis.requestAnimationFrame(wheelTick);
    };
    container.addEventListener('wheel', event => {
      if (!state.gesturesEnabled || !state.zoom) return;
      release();
      if (!supports3D() || typeof globalThis.requestAnimationFrame !== 'function') return;
      event.preventDefault(); event.stopImmediatePropagation();
      const unit = event.deltaMode === 1 ? 33 : event.deltaMode === 2 ? 800 : 1;
      const current = Number(map.getZoom());
      if (!Number.isFinite(current)) return;
      const step = clamp(-(event.deltaY || 0) * unit / 150, -1, 1);
      wheelGoal = clamp((wheelGoal ?? current) + step, 3, 21);
      wheelPoint = {x: event.clientX, y: event.clientY};
      if (!wheelFrame) {
        wheelSet = null;
        wheelFrame = globalThis.requestAnimationFrame(wheelTick);
      }
    }, {capture: true, passive: false});
    // Own touch geometry so zoom, tilt and rotation happen in one gesture.
    // Mouse and keyboard gestures stay with Google Maps.
    container.addEventListener('touchstart', event => {
      if (!state.gesturesEnabled || cancelledTouchSequence) return;
      // Let the browser synthesize clicks for Maps' own +/- controls.
      if (nativeCameraControl(event.target)) {
        touchOnControl = true;
        previous = null;
        return;
      }
      if (touchOnControl) return;
      event.preventDefault(); event.stopImmediatePropagation();
      state.stopWheel?.();
      if (!previous) {
        startedAt = performance.now(); maxTouches = 0;
        travel = 0; touchReleased = false; multiTouchMoved = false;
        lastTwoFingerPoint = null;
      }
      maxTouches = Math.max(maxTouches, event.touches.length);
      if (event.touches.length > 1) releaseTouch();
      previous = {...touchPose(event.touches), count: event.touches.length};
      if (previous.count > 1) lastTwoFingerPoint = {x: previous.x, y: previous.y};
    }, {capture: true, passive: false});
    container.addEventListener('touchmove', event => {
      if (!state.gesturesEnabled || touchOnControl || cancelledTouchSequence) return;
      event.preventDefault(); event.stopImmediatePropagation();
      const next = {...touchPose(event.touches), count: event.touches.length};
      if (next.count > 1) lastTwoFingerPoint = {x: next.x, y: next.y};
      if (!previous || previous.count !== next.count) { previous = next; return; }
      travel += Math.hypot(next.x - previous.x, next.y - previous.y) +
          Math.abs(next.span - previous.span);
      if (next.count > 1 && (travel > 2 ||
          Math.abs(delta(previous.angle, next.angle)) > 1.5)) {
        multiTouchMoved = true;
      }
      if (next.count > 1 || travel >= 6) releaseTouch();
      if (!touchReleased) { previous = next; return; }
      if (next.count > 1) {
        const twist = state.rotate ? delta(previous.angle, next.angle) : 0;
        // Overlapping touches can briefly report a zero span (log2(0)), and
        // sparse frames can leap: bound the zoom step per event.
        const ratio = previous.span >= 5 && next.span >= 5
          ? next.span / previous.span : 1;
        const zoomDelta = clamp(Math.log2(ratio), -0.4, 0.4);
        const vertical = next.y - previous.y;
        // Tilt follows zoom by itself; a hand tilt is only a deliberate
        // two-finger drag: both fingers up (or both down) together, mostly
        // vertical, with no pinch or twist in the frame. A pinch whose
        // fingers drift vertically stays a zoom: hand tilt never takes a
        // frame's zoom, and every other frame binds the tilt to the zoom.
        const dyA = next.ay - previous.ay, dyB = next.by - previous.by;
        const tilting = state.tilt && Math.sign(dyA) === Math.sign(dyB) &&
          Math.min(Math.abs(dyA), Math.abs(dyB)) > 1 &&
          Math.abs(vertical) > 2 * Math.abs(next.x - previous.x) &&
          Math.abs(twist) < 2 && Math.abs(zoomDelta) < .01;
        // Zoom about the *previous* focal point; the midpoint translation
        // then carries that road point to the fingers' new position.
        zoomAt(zoomDelta, previous.x, previous.y,
          supports3D() ? {
            heading: ((map.getHeading() || 0) - twist + 360) % 360,
            ...(tilting ? {tilt: clamp((map.getTilt() || 0) - vertical * .3, 0,
              sdkMaxTilt(Number(map.getZoom())))} : {})
          } : {},
          tilting ? 0 : next.x - previous.x,
          tilting ? 0 : next.y - previous.y);
      } else if (state.scroll) pan(state, next.x - previous.x, next.y - previous.y);
      previous = next;
    }, {capture: true, passive: false});
    const end = event => {
      if (event.type === 'touchcancel') {
        // An OS interruption can leave one finger on the map. Discard all
        // tap and pinch history until the final touch lifts.
        cancelledTouchSequence = event.touches.length > 0;
        previous = null; touchReleased = false; multiTouchMoved = false;
        lastTwoFingerPoint = null; maxTouches = 0; travel = 0;
        lastTap = -Infinity; lastTapPoint = null; touchOnControl = false;
        return;
      }
      if (cancelledTouchSequence) {
        if (!event.touches.length) cancelledTouchSequence = false;
        return;
      }
      if (touchOnControl) {
        if (!event.touches.length) touchOnControl = false;
        return;
      }
      if (!state.gesturesEnabled) { previous = null; return; }
      event.preventDefault(); event.stopImmediatePropagation();
      if (event.touches.length) {
        // A two-finger tap ends one finger at a time: keep its midpoint.
        if (previous?.count > 1) lastTwoFingerPoint = {x: previous.x, y: previous.y};
        previous = {...touchPose(event.touches), count: event.touches.length};
        return;
      }
      if (state.zoom && previous && performance.now() - startedAt < 300 && travel < 8) {
        if (maxTouches > 1) {
          // Two stationary fingers zoom out one level; a subtle pinch
          // already moved the camera and is not undone here.
          if (!multiTouchMoved) {
            releaseTouch();
            const focus = lastTwoFingerPoint || previous;
            zoomAt(-1, focus.x, focus.y);
          }
          lastTap = -Infinity; lastTapPoint = null;
        } else {
          const now = performance.now();
          const nearby = lastTapPoint != null &&
            Math.hypot(previous.x - lastTapPoint.x, previous.y - lastTapPoint.y) <= 32;
          if (now - lastTap < 300 && nearby) {
            releaseTouch();
            zoomAt(1, previous.x, previous.y);
            lastTap = -Infinity; lastTapPoint = null;
          } else {
            lastTap = now;
            lastTapPoint = {x: previous.x, y: previous.y};
          }
        }
      } else {
        lastTap = -Infinity; lastTapPoint = null;
      }
      previous = null; touchReleased = false; multiTouchMoved = false;
      lastTwoFingerPoint = null;
    };
    container.addEventListener('touchend', end, {capture: true, passive: false});
    container.addEventListener('touchcancel', end, {capture: true, passive: false});
    // Flutter removes the platform view at dispose. The map is then taken
    // back for the next screen (see reuse below): its listeners and
    // overlays are cleared, its container leaves the dead plugin element,
    // and the gesture state waits in the pool. Dart asks first
    // (riderMapCamera.release from CustomGoogleMap.dispose); the observer
    // is the fallback, and either way the element must be out of the DOM,
    // a frame later, before anything is touched.
    let observer = null;
    let parked = false;
    const stopWatching = () => {
      try { observer?.disconnect(); } catch (_) { /* best effort */ }
      observer = null;
    };
    const park = () => {
      if (parked) return;
      parked = true;
      stopWatching();
      if (states.get(state.id) === state) states.delete(state.id);
      state.callbacks.clear();
      try { endFlight(false); } catch (_) { /* best effort */ }
      try { stopWheel(); } catch (_) { /* best effort */ }
      state.claim = false;
      state.setGesturesEnabled(true);
      Object.assign(state, {scroll: true, zoom: true, rotate: true, tilt: true,
        tiltFollowsZoom: true});
      poolMap(state);
    };
    const parkOnceRemoved = () => {
      if (parked || state.div.isConnected) return;
      // Maps may still be finishing a frame for this element: a short
      // pause, then a last check that Flutter has not put it back.
      const div = state.div;
      setTimeout(() => {
        if (!parked && state.div === div && !div.isConnected) park();
      }, 250);
    };
    const watch = () => {
      stopWatching();
      // Any DOM change while the element is out of the document counts: a
      // map mounted and parked again within a frame (Home between Plan
      // your ride and the categories screen) is never seen connected by a
      // callback.
      observer = new MutationObserver(() => {
        if (!state.div.isConnected) parkOnceRemoved();
      });
      observer.observe(document.body, {childList: true, subtree: true});
    };
    state.release = parkOnceRemoved;
    // A pooled map is given to the next plugin element: same Map, same
    // container and gesture listeners, a new element around it and a new id.
    state.reattach = (nextDiv, nextId) => {
      parked = false;
      state.div = nextDiv;
      state.id = nextId;
      states.set(nextId, state);
      watch();
    };
    watch();
  }
  // Reuse. google.maps.Map has no destroy(), and the Maps script keeps an
  // internal list of every map's container (a heap snapshot after dispose
  // shows the Map object held through that list), while google_maps_flutter_web
  // keeps every map's element in the platform view registry for the life of
  // the page. Measured before this: each booking left 5-6 whole maps behind
  // (about 1,400 DOM nodes, 900 listeners and 8 MB of heap a booking, and
  // on a vector map a WebGL context each), until the page was killed. So a
  // map Flutter has removed is not thrown away: its listeners and overlays
  // are cleared and it waits in a small pool; the next plugin element gets
  // the same Map with its container moved inside, as Google itself advises
  // (create a map once, reuse it). Beyond the pool a map is gutted instead.
  const pool = [];
  const POOL_MAX = 2;
  let created = 0, recycled = 0, pooledTotal = 0;
  const overlaysOf = map => (map.__moveraOverlays ||= new Set());
  function clearMapForReuse(state) {
    const {map, container} = state;
    try { sdk.event.clearInstanceListeners(map); } catch (_) { /* best effort */ }
    for (const overlayItem of [...overlaysOf(map)]) {
      try { overlayItem.setMap(null); } catch (_) { /* best effort */ }
    }
    overlaysOf(map).clear();
    try { container.remove(); } catch (_) { /* best effort */ }
  }
  function poolMap(state) {
    clearMapForReuse(state);
    if (pool.length >= POOL_MAX) {
      releaseMapResources(state.map, state.container);
      return;
    }
    pool.push(state);
    pooledTotal += 1;
  }
  function reuseMap(state, div, options, id) {
    const {map, container} = state;
    container.style.position = 'absolute';
    container.style.inset = '0';
    container.style.width = '100%';
    container.style.height = '100%';
    div.appendChild(container);
    // mapId cannot change after the first render (every rider map uses the
    // same one); the rest of the options are applied afresh.
    const {mapId, ...rest} = options || {};
    map.setOptions({...rest, isFractionalZoomEnabled: true});
    if (rest.center) map.setCenter(rest.center);
    if (rest.zoom != null) map.setZoom(rest.zoom);
    map.setHeading(rest.heading || 0);
    map.setTilt(rest.tilt || 0);
    state.reattach(div, id);
    // google_maps_flutter_web reports a map as created (onMapCreated) on its
    // first 'tilesloaded', which Google fires once per Map: a reused map
    // whose tiles are already loaded never fires it again, so the screen
    // never got its controller (Select ride stayed uncreated, Set pickup
    // never moved off the opening view). The plugin listens right after
    // this constructor returns, so the event is replayed on the next task.
    // The camera is set again then too, now that the map's new element is
    // laid out, so the screen opens on its own target, not the last view.
    setTimeout(() => {
      try {
        const camera = {heading: rest.heading || 0, tilt: rest.tilt || 0};
        if (rest.center) camera.center = rest.center;
        if (rest.zoom != null) camera.zoom = rest.zoom;
        map.moveCamera(camera);
      } catch (_) { /* best effort */ }
      try { sdk.event.trigger(map, 'tilesloaded'); } catch (_) { /* best effort */ }
    }, 0);
    recycled += 1;
    return map;
  }
  // Markers, lines, shapes and layers are tracked per map, so a reused map
  // starts empty: the plugin removes them only when told, and a disposed
  // controller never is.
  function trackOverlays() {
    const hook = instance => {
      if (!instance || instance.__moveraTracked) return;
      instance.__moveraTracked = true;
      const nativeSetMap = instance.setMap;
      if (typeof nativeSetMap !== 'function') return;
      instance.setMap = function(next) {
        try {
          const previous = this.getMap?.();
          if (previous) overlaysOf(previous).delete(this);
          if (next) overlaysOf(next).add(this);
        } catch (_) { /* best effort */ }
        return nativeSetMap.call(this, next);
      };
    };
    for (const name of ['Marker', 'Polyline', 'Polygon', 'Circle', 'Rectangle',
        'TrafficLayer', 'TransitLayer', 'BicyclingLayer', 'GroundOverlay']) {
      const Native = sdk[name];
      if (typeof Native !== 'function') continue;
      sdk[name] = new Proxy(Native, {
        construct(target, args) {
          const instance = Reflect.construct(target, args);
          hook(instance);
          try {
            const map = instance.getMap?.();
            if (map) overlaysOf(map).add(instance);
          } catch (_) { /* best effort */ }
          return instance;
        }
      });
    }
    // The plugin's traffic layer is attached with set('map', map).
    const Layer = sdk.TrafficLayer;
    if (typeof Layer === 'function' && Layer.prototype && !Layer.prototype.__moveraSetHooked) {
      Layer.prototype.__moveraSetHooked = true;
      const nativeSet = Layer.prototype.set;
      if (typeof nativeSet === 'function') {
        Layer.prototype.set = function(key, value) {
          if (key === 'map') {
            try {
              const previous = this.getMap?.();
              if (previous) overlaysOf(previous).delete(this);
              if (value) overlaysOf(value).add(this);
            } catch (_) { /* best effort */ }
          }
          return nativeSet.call(this, key, value);
        };
      }
    }
  }
  // google.maps.Map has no destroy(). A map whose <div> Flutter has removed
  // keeps its tiles, its listeners and, on a vector map, its WebGL context
  // for as long as the <div> is referenced, and google_maps_flutter_web
  // keeps every map's <div> in the platform view registry for the life of
  // the page: measured, each booking left 5-6 whole maps behind (about
  // 1,700 DOM nodes, 1,000 listeners and 20 MB of heap per booking). Safari
  // allows about 16 WebGL contexts per page and evicts the oldest (often
  // Flutter's own) once there are more, which blanks the screen until
  // Flutter rebuilds its surface. So the WebGL contexts a removed map owns
  // are given back explicitly and the DOM under its <div> is dropped; the
  // empty <div> and the Map object the registry keeps are small.
  let released = 0, contextsReleased = 0;
  function releaseMapResources(map, div) {
    try { sdk.event.clearInstanceListeners(map); } catch (_) { /* best effort */ }
    try {
      div.querySelectorAll('canvas').forEach(canvas => {
        const kind = canvas.__moveraContext;
        if (kind === 'webgl' || kind === 'webgl2') {
          try {
            const gl = canvas.getContext(kind);
            const ext = gl && gl.getExtension('WEBGL_lose_context');
            if (ext && !gl.isContextLost()) { ext.loseContext(); contextsReleased += 1; }
          } catch (_) { /* best effort */ }
        }
        try { canvas.width = 0; canvas.height = 0; } catch (_) { /* best effort */ }
      });
    } catch (_) { /* best effort */ }
    try { div.replaceChildren(); } catch (_) { /* best effort */ }
    released += 1;
  }
  // Which context each canvas was given, so a removed map's WebGL contexts
  // can be found without creating one on a canvas that had none.
  try {
    const nativeGetContext = HTMLCanvasElement.prototype.getContext;
    HTMLCanvasElement.prototype.getContext = function(kind, ...rest) {
      const context = nativeGetContext.call(this, kind, ...rest);
      if (context && !this.__moveraContext) this.__moveraContext = String(kind);
      return context;
    };
  } catch (_) { /* best effort: the release then only drops the DOM */ }
  function installSdk() {
    sdk = globalThis.google.maps;
    trackOverlays();
    const NativeMap = sdk.Map;
    sdk.Map = new Proxy(NativeMap, {
      construct(target, args) {
        const [div, options = {}] = args;
        const match = /^plugins\.flutter\.io\/google_maps_(\d+)$/.exec(div?.id || '');
        if (!match) return Reflect.construct(target, args);
        const id = Number(match[1]);
        while (pool.length) {
          const state = pool.pop();
          try {
            return reuseMap(state, div, options, id);
          } catch (error) {
            // A map that cannot be taken back is dropped; a new one is made.
            try { releaseMapResources(state.map, state.container); } catch (_) { /* best effort */ }
            console.warn('rider_map_camera: map reuse failed', error);
          }
        }
        // Fractional zoom: pinch and app eases move in small steps (raster
        // tiles default to whole levels, so 11.7 would snap to 12).
        const map = Reflect.construct(target, [div, {...options, isFractionalZoomEnabled: true}]);
        created += 1;
        install(map, div, id);
        return map;
      }
    });
  }
  const sdkLoaded = () => typeof globalThis.google?.maps?.Map === 'function' &&
    typeof globalThis.google.maps.OverlayView === 'function';
  if (sdkLoaded()) installSdk();
  else {
    const poll = setInterval(() => {
      if (!sdkLoaded()) return;
      clearInterval(poll);
      installSdk();
    }, 25);
  }
  const div_isConnected = div => { try { return !!div.isConnected; } catch (_) { return false; } };
  globalThis.riderMapCamera = {
    ready() { return sdk !== null; },
    has(id) { return states.has(id); },
    // True on a vector map, false on raster, null while Google decides.
    supports3D(id) {
      const state = states.get(id); if (!state) return null;
      const type = state.map.getRenderingType?.();
      return type === sdk.RenderingType.VECTOR ? true :
        type === sdk.RenderingType.RASTER ? false : null;
    },
    gestures(id, scroll, zoom, rotate, tilt) {
      const state = states.get(id); if (!state) return;
      Object.assign(state, {scroll: !!scroll, zoom: !!zoom, rotate: !!rotate, tilt: !!tilt});
      state.setGesturesEnabled(!!(scroll || zoom || rotate || tilt));
    },
    // Pickup pin screens stay flat while the rider zooms them.
    tiltFollowsZoom(id, enabled) {
      const state = states.get(id); if (state) state.tiltFollowsZoom = !!enabled;
    },
    listen(id, callback) {
      const state = states.get(id); state?.callbacks.add(callback);
      return () => state?.callbacks.delete(callback);
    },
    // Dart disposed this map's widget: release it once Flutter has taken
    // its <div> out of the DOM (the observer above does the same).
    release(id) {
      const state = states.get(id);
      if (!state) return;
      if (div_isConnected(state.div)) {
        // Flutter removes the element on its next frame; wait for it.
        setTimeout(() => state.release?.(), 50);
        setTimeout(() => state.release?.(), 600);
        return;
      }
      state.release?.();
    },
    // Live maps, maps created and reused, maps waiting in the pool and
    // what was given back: evidence for the lifecycle probe and the app's
    // own log.
    stats() {
      const ids = [...states.entries()].map(([key, state]) =>
        `${key}${div_isConnected(state.div) ? '' : ':detached'}`);
      return {live: states.size, created, recycled, pooled: pool.length,
        pooledTotal, released, contextsReleased, ids};
    },
    claim(id) {
      const state = states.get(id); if (state) state.claim = true;
    },
    // Flies the camera on the frame clock; resolves true when it lands,
    // false when cancelled (a finger, a newer command). Null: no such map
    // or no frame clock, and Dart steps the flight itself.
    flight(id, lat, lng, zoom, heading, tilt, ms) {
      const state = states.get(id);
      if (!state || typeof globalThis.requestAnimationFrame !== 'function') return null;
      return state.flight({lat, lng, zoom, heading, tilt}, ms);
    },
    // The follow glide on the frame clock; same results as flight().
    glide(id, lat, lng, zoom, heading, tilt, ms) {
      const state = states.get(id);
      if (!state || typeof globalThis.requestAnimationFrame !== 'function') return null;
      return state.glide({lat, lng, zoom, heading, tilt}, ms);
    },
    retarget(id, lat, lng, zoom, heading, tilt) {
      states.get(id)?.retarget({lat, lng, zoom, heading, tilt});
    },
    cancelFlight(id) {
      return states.get(id)?.cancelFlight() ?? null;
    },
    // Test/verification hook: the live camera of a map.
    camera(id) {
      const state = states.get(id); if (!state) return null;
      const m = state.map;
      return {zoom: Number(m.getZoom()), tilt: m.getTilt() || 0,
        heading: m.getHeading() || 0, vector: state.supports3D()};
    },
  };
})();
