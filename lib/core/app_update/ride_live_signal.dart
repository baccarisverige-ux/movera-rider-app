import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:movera_rider/core/app_update/min_app_version.dart';
import 'package:movera_rider/core/logging/app_log.dart';

/// Contract v0.18.154 P16c (`contract.json#appUpdate.apps`): "a ride is live"
/// for the minimum-version block. True while
/// - any ride screen of a live ride is mounted (the on-demand flow and the
///   booked-ride live screen, which saves no snapshot; the ride's rating /
///   tip / receipt screens too, so the block comes at Home);
/// - the ride snapshot store says a live ride is saved;
/// - at start, a stored live ride or a server active trip exists;
/// - and until the app has confirmed there is no live ride (unknown never
///   blocks).
class RideLiveSignal extends ChangeNotifier implements ValueListenable<bool> {
  RideLiveSignal({
    required ValueListenable<bool> snapshotLive,
    Future<bool> Function()? storedLive,
    Future<bool> Function()? serverLive,
    bool watchRule = true,
  }) : _snapshotLive = snapshotLive,
       _storedLiveCheck = storedLive,
       _serverLiveCheck = serverLive {
    _snapshotLive.addListener(_onSnapshot);
    if (watchRule) {
      MinAppVersion.rule.addListener(_maybeCheck);
      MinAppVersion.serverSaid.addListener(_maybeCheck);
    }
  }

  /// The app's signal (wired in di.dart); a default that never blocks
  /// until checked.
  static RideLiveSignal? instance;

  final ValueListenable<bool> _snapshotLive;
  final Future<bool> Function()? _storedLiveCheck;
  final Future<bool> Function()? _serverLiveCheck;

  int _screens = 0;
  bool _known = false;
  bool _startLive = false;
  Future<void>? _checking;

  /// True: a ride is (or may be) live; the block waits.
  @override
  bool get value =>
      !_known || _screens > 0 || _snapshotLive.value || _startLive;

  /// The start check answered (stored ride + server active trip).
  bool get known => _known;

  void enterRideScreen() {
    _screens++;
    _notifySafely();
  }

  void leaveRideScreen() {
    if (_screens > 0) _screens--;
    _notifySafely();
  }

  bool _disposed = false;

  /// Screens enter and leave while the tree builds or unmounts: tell the
  /// listeners after the frame then.
  void _notifySafely() {
    if (_disposed) return;
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle ||
        phase == SchedulerPhase.postFrameCallbacks) {
      notifyListeners();
      return;
    }
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!_disposed) notifyListeners();
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  /// The store decides from its first save or clear on.
  void _onSnapshot() {
    _startLive = false;
    _notifySafely();
  }

  void _maybeCheck() {
    if (!_known && MinAppVersion.required) unawaited(check());
  }

  /// Reads the stored ride and the server's active trip once; an error
  /// leaves the state unknown (no block) and is tried again later.
  Future<void> check() => _checking ??= _check().whenComplete(() {
    _checking = null;
  });

  Future<void> _check() async {
    try {
      final stored = await (_storedLiveCheck?.call() ?? Future.value(false));
      final server = stored
          ? true
          : await (_serverLiveCheck?.call() ?? Future.value(false));
      _startLive = stored || server;
      _known = true;
    } catch (error) {
      AppLog.warning(
        'min_version.ride_check_failed',
        extra: {'error': error.toString()},
      );
    }
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _snapshotLive.removeListener(_onSnapshot);
    MinAppVersion.rule.removeListener(_maybeCheck);
    MinAppVersion.serverSaid.removeListener(_maybeCheck);
    super.dispose();
  }
}

/// Counts its State as a mounted ride screen in [RideLiveSignal.instance].
mixin RideScreenLive<T extends StatefulWidget> on State<T> {
  RideLiveSignal? _signal;

  @override
  void initState() {
    super.initState();
    _signal = RideLiveSignal.instance?..enterRideScreen();
  }

  @override
  void dispose() {
    _signal?.leaveRideScreen();
    super.dispose();
  }
}
