import 'dart:convert';

import 'package:flutter/scheduler.dart';
import 'package:movera_rider/core/debug/movera_qa.dart';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

String? _firstSurface;
bool _homeBuilt = false;

void reportRestoreSurface(String surface) {
  globalContext.setProperty('moveraRestoreSurface'.toJS, surface.toJS);
  if (surface != 'hold') {
    _firstSurface ??= surface;
    globalContext.setProperty('moveraFirstSurface'.toJS, _firstSurface!.toJS);
  }
}

void reportHomeBuilt() {
  _homeBuilt = true;
  globalContext.setProperty('moveraHomeBuilt'.toJS, true.toJS);
}

void reportMapOwner(String? owner, int generation) {
  globalContext.setProperty('moveraMapOwner'.toJS, (owner ?? '').toJS);
  globalContext.setProperty('moveraMapGeneration'.toJS, generation.toJS);
}

void reportPuckHeading(double heading, {required bool compass}) {
  globalContext.setProperty('moveraPuckHeading'.toJS, heading.toJS);
  globalContext.setProperty('moveraCompassActive'.toJS, compass.toJS);
  try {
    final debug = globalContext.getProperty('moveraHeadingDebug'.toJS);
    if (debug.isUndefined || debug.isNull) return;
    final object = debug as JSObject;
    object.setProperty('dartHeading'.toJS, heading.toJS);
    object.setProperty('dartCompassActive'.toJS, compass.toJS);
    object.setProperty('puckHeading'.toJS, heading.toJS);
  } catch (_) {
    // Debug-only QA bridge; a missing JS object is not an error.
  }
}

bool get debugHomeBuilt => _homeBuilt;

void reportSafetySnapshot(String json) {
  globalContext.setProperty('moveraSafetySnapshotJson'.toJS, json.toJS);
}

void installSafetyQaOpener(void Function() open) {
  if (!moveraQaHooksEnabled) return;
  globalContext.setProperty(
    'moveraOpenSafety'.toJS,
    (() {
      try {
        open();
        return 'ok'.toJS;
      } catch (_) {
        return 'error'.toJS;
      }
    }).toJS,
  );
}

void installSafetyNavigationBridge(bool Function() open) {
  // This bridge is intentionally available in public web builds. It can only
  // navigate to the same Safety screen the rider can already open from the
  // drawer; it cannot seed rides, alter matching, or mutate Safety state.
  globalContext.setProperty(
    'moveraOpenSafety'.toJS,
    (() {
      try {
        return (open() ? 'ok' : 'unavailable').toJS;
      } catch (_) {
        return 'error'.toJS;
      }
    }).toJS,
  );
}

void reportSearchSnapshot(String json) {
  // rider-r5-19: carries the pickup address and coordinates, so it is a QA
  // hook like the others (docs/QA_HOOKS.md), never on a public release.
  if (!moveraQaHooksEnabled) return;
  globalContext.setProperty('moveraSearchSnapshotJson'.toJS, json.toJS);
}

void installMatchingQaHooks({
  required void Function() hold,
  required void Function() assign,
  required void Function(int seconds) advance,
}) {
  if (!moveraQaHooksEnabled) return;
  globalContext.setProperty(
    'moveraHoldMatching'.toJS,
    (() {
      try {
        hold();
        return 'ok'.toJS;
      } catch (_) {
        return 'error'.toJS;
      }
    }).toJS,
  );
  globalContext.setProperty(
    'moveraAssignDriver'.toJS,
    (() {
      try {
        assign();
        return 'ok'.toJS;
      } catch (_) {
        return 'error'.toJS;
      }
    }).toJS,
  );
  globalContext.setProperty(
    'moveraAdvanceSearch'.toJS,
    ((JSNumber seconds) {
      try {
        advance(seconds.toDartDouble.round());
        return 'ok'.toJS;
      } catch (_) {
        return 'error'.toJS;
      }
    }).toJS,
  );
}

void Function()? _rideCheckQaListener;

/// Installs `window.moveraSimulateRideCheck(type, detail?)` for debug /
/// MOVERA_QA builds only. `type` is a trigger (`droppedFar`, `longStop`,
/// `offRoute`, `possibleCrash`; older event names still work) and `detail`
/// an optional object for the reason line, e.g. `{place: 'Odenplan'}` or
/// `{distanceMeters: 1200}`. It queues the check and tells the in-trip
/// screen, which opens the card at once (or on its next start), so a public
/// release must never expose it.
void installRideCheckQaHook() {
  if (!moveraQaHooksEnabled) return;
  globalContext.setProperty(
    'moveraSimulateRideCheck'.toJS,
    ((JSAny? type, JSAny? detail) {
      final value = type == null || type.isUndefined || type.isNull
          ? 'unexpectedStop'
          : type.dartify().toString();
      globalContext.setProperty('_moveraPendingRideCheck'.toJS, value.toJS);
      String? detailJson;
      if (detail != null && !detail.isUndefined && !detail.isNull) {
        try {
          final raw = detail.dartify();
          detailJson = raw is String ? raw : jsonEncode(raw);
        } catch (_) {
          detailJson = null;
        }
      }
      globalContext.setProperty(
        '_moveraPendingRideCheckDetail'.toJS,
        detailJson?.toJS,
      );
      _rideCheckQaListener?.call();
      return true.toJS;
    }).toJS,
  );
}

String? pendingRideCheckType() {
  // A value set by page script in a public build is ignored.
  if (!moveraQaHooksEnabled) return null;
  try {
    final value = globalContext.getProperty('_moveraPendingRideCheck'.toJS);
    if (value.isUndefined || value.isNull) return null;
    return (value as JSString).toDart;
  } catch (_) {
    return null;
  }
}

/// The optional `detail` passed with the queued check, as JSON.
String? pendingRideCheckDetail() {
  if (!moveraQaHooksEnabled) return null;
  try {
    final value = globalContext.getProperty(
      '_moveraPendingRideCheckDetail'.toJS,
    );
    if (value.isUndefined || value.isNull) return null;
    return (value as JSString).toDart;
  } catch (_) {
    return null;
  }
}

void clearPendingRideCheck() {
  globalContext.setProperty('_moveraPendingRideCheck'.toJS, null);
  globalContext.setProperty('_moveraPendingRideCheckDetail'.toJS, null);
}

/// Called whenever `moveraSimulateRideCheck` queues a check (QA builds).
void listenForRideCheckQa(void Function()? listener) {
  _rideCheckQaListener = listener;
}

/// Read-only Ride check state for QA scripts (`moveraRideCheckSnapshotJson`).
void reportRideCheckSnapshot(String json) {
  if (!moveraQaHooksEnabled) return;
  globalContext.setProperty('moveraRideCheckSnapshotJson'.toJS, json.toJS);
}

/// Frame timings for the sheet-performance probe
/// (docs/select-ride-sheet-performance.md): MOVERA_QA builds only.
/// `window.moveraFrameTimings()` returns the frames since the previous
/// call as JSON `{"frames": n, "build": [ms], "raster": [ms],
/// "total": [ms]}`, so a browser test can tell Dart build time from the
/// engine's raster time per frame. The engine only records timings while a
/// callback is registered, so none of this runs on a public build.
final List<FrameTiming> _frameTimings = <FrameTiming>[];
const int _frameTimingsKept = 4000;

void installFrameTimingQaHook() {
  if (!moveraQaHooksEnabled) return;
  SchedulerBinding.instance.addTimingsCallback((timings) {
    _frameTimings.addAll(timings);
    if (_frameTimings.length > _frameTimingsKept) {
      _frameTimings.removeRange(0, _frameTimings.length - _frameTimingsKept);
    }
  });
  globalContext.setProperty(
    'moveraFrameTimings'.toJS,
    (() {
      final taken = List<FrameTiming>.of(_frameTimings);
      _frameTimings.clear();
      double ms(Duration d) => d.inMicroseconds / 1000;
      return jsonEncode({
        'frames': taken.length,
        'build': [for (final t in taken) ms(t.buildDuration)],
        'raster': [for (final t in taken) ms(t.rasterDuration)],
        'total': [for (final t in taken) ms(t.totalSpan)],
      }).toJS;
    }).toJS,
  );
}
