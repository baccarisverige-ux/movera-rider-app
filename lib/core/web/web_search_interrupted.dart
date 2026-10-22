import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:movera_rider/core/web/web_search_interrupted_io.dart'
    if (dart.library.js_interop) 'package:movera_rider/core/web/web_search_interrupted_web.dart';

/// Remember a ride is live, so a reload can explain itself afterwards.
void markSearchLive() => webMarkSearchLive();

/// The ride ended deliberately; forget it.
void clearSearchLive() => (debugClearSearchLive ?? webClearSearchLive)();

/// True once if a ride was still live when the previous document ended.
bool takeWebSearchInterrupted() =>
    (debugTakeWebSearchInterrupted ?? webTakeSearchInterrupted)();

/// Tests: stands in for the web session flag, which non-web builds lack.
@visibleForTesting
bool Function()? debugTakeWebSearchInterrupted;

/// Tests: sees [clearSearchLive], which non-web builds make a no-op.
@visibleForTesting
void Function()? debugClearSearchLive;
