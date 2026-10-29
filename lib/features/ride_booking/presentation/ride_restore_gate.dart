import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:movera_rider/app/navigator_key.dart';
import 'package:movera_rider/core/debug/web_qa_hooks.dart';
import 'package:movera_rider/core/web/web_overlay.dart';
import 'package:movera_rider/features/auth/presentation/start_error.dart';
import 'package:movera_rider/features/auth/presentation/rider_name.dart';
import 'package:movera_rider/features/auth/presentation/sign_in.dart';
import 'package:movera_rider/features/ride_booking/application/ride_restore_coordinator.dart';

class RideRestoreGate extends StatefulWidget {
  const RideRestoreGate({super.key});

  static final gateKey = GlobalKey<RideRestoreGateState>();

  /// Owner 2026-10-29, decision 2 (from the driver app's start screen): how
  /// long the start waits in silence before a spinner shows.
  static const spinnerAfter = Duration(seconds: 2);

  /// Tests: the first page instead of [RideRestoreCoordinator.root].
  @visibleForTesting
  static Future<Widget> Function()? debugRoot;

  static void show(Widget page) {
    gateKey.currentState?.show(page);
  }

  @override
  State<RideRestoreGate> createState() => RideRestoreGateState();
}

class RideRestoreGateState extends State<RideRestoreGate> {
  Widget? _child;

  /// The hook handed to the coordinator, stored once. A method tear-off is
  /// `==` but not `identical` to a later tear-off, so comparing `show` in
  /// [dispose] never matched and left the coordinator calling a dead State.
  late final void Function(Widget page) _hook = show;

  void show(Widget page) {
    if (!mounted) return;
    setState(() => _setChild(page));
    _lockHomeIfRoot();
  }

  void _setChild(Widget page) {
    _child = page;
    // Ride and notification openers must not draw over the sign-in flow.
    RideRestoreCoordinator.instance.authRootShowing =
        page is SignIn || page is RiderNameScreen;
  }

  void _lockHomeIfRoot() {
    final nav = moveraNavigatorKey.currentState;
    final atRoot = nav == null || !nav.canPop();
    final home =
        RideRestoreCoordinator.instance.showing == RestoredSurface.home;
    setWebHomeLock(atRoot && home);
  }

  @override
  void initState() {
    super.initState();
    reportRestoreSurface('hold');
    RideRestoreCoordinator.instance.onReplaceRoot = _hook;
    _start();
  }

  /// Owner decision 2: a spinner after 2 s; a failed start says so with
  /// Try again, Sign out and Contact support.
  bool _slow = false;
  bool _failed = false;
  Timer? _slowTimer;

  void _start() {
    _slowTimer?.cancel();
    _slow = false;
    _slowTimer = Timer(RideRestoreGate.spinnerAfter, () {
      if (mounted) setState(() => _slow = true);
    });
    // pagehide used to wipe the snapshot on public web. A crash/reload must
    // keep the ride so cold start can restore it. Tab switch already keeps
    // the in-progress ride (no visibilitychange listener).
    (RideRestoreGate.debugRoot ?? RideRestoreCoordinator.instance.root)()
        .then((page) {
          _slowTimer?.cancel();
          if (!mounted) return;
          setState(() => _setChild(page));
          _lockHomeIfRoot();
        })
        .catchError((Object _) {
          _slowTimer?.cancel();
          if (mounted) setState(() => _failed = true);
        });
  }

  void _retry() => setState(() {
    _failed = false;
    _start();
  });

  @override
  void dispose() {
    _slowTimer?.cancel();
    final coordinator = RideRestoreCoordinator.instance;
    // A newer gate may already have installed its own hook; leave that one.
    if (identical(coordinator.onReplaceRoot, _hook)) {
      coordinator.onReplaceRoot = null;
      coordinator.authRootShowing = false;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final child =
        _child ??
        (_failed
            ? StartError(
                onRetry: _retry,
                onSignedOut: () => show(const SignIn()),
              )
            : ColoredBox(
                color: const Color(0xFFFFFFFF),
                child: _slow
                    ? const Center(
                        key: ValueKey('start-spinner'),
                        child: CircularProgressIndicator(),
                      )
                    : const SizedBox.expand(),
              ));
    return PopScope(canPop: !kIsWeb, child: child);
  }
}
