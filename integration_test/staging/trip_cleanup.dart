part of 'trip_run.dart';

/// The clean-up every run reaches: each trip the run booked is closed
/// (rider cancel up to the arrival, else a driver cancel on board), the
/// phone is brought back to Home, and the test driver goes offline (a
/// driver left online takes the next run's offers).
extension _TripCleanup on TripRun {
  Future<void> _cleanup({required DateTime until}) async {
    await _closeTrips(until: until);
    await _backHome(until: until);
  }

  /// The HTTP-only half of the clean-up (no pump): the watchdog runs it
  /// when a pump never returned.
  Future<void> _closeTrips({required DateTime until}) async {
    const title = 'no open test trip is left';
    Future<ApiAnswer> boxed(Future<ApiAnswer> call) {
      var left = until.difference(DateTime.now());
      if (left < const Duration(seconds: 5)) left = const Duration(seconds: 5);
      return call.timeout(
        left,
        onTimeout: () => const ApiAnswer(0, null, error: 'TimeoutException'),
      );
    }

    refreshRiderToken();
    // A booking whose answer the app got but the test did not see.
    if (riderApi.signedIn) {
      final open = await riderApi.openTripIds().timeout(
        const Duration(seconds: 20),
        onTimeout: () => null,
      );
      for (final id in open ?? const <String>{}) {
        if (!booked.contains(id)) booked.add(id);
      }
    }
    if (booked.isEmpty) {
      return log.skip('CLEANUP', title, 'no trip was booked');
    }
    final lines = <String>[];
    var allClosed = true;
    for (final id in booked) {
      try {
        var answer = await boxed(riderApi.trip(id));
        var status = answer.map?['status'] as String?;
        var how = 'nothing to do';
        if (status != null && !terminalStatuses.contains(status)) {
          final version = (answer.map!['version'] as num).toInt();
          final byRider = riderCancellable.contains(status);
          final done = await boxed(
            byRider
                ? riderApi.cancel(id, version, 'plans_changed')
                : peer.api.cancel(id, version, 'other_on_trip'),
          );
          how = '${byRider ? 'rider' : 'driver'} cancel ${done.short}';
          answer = await boxed(riderApi.trip(id));
          status = answer.map?['status'] as String?;
        }
        final closed = status != null && terminalStatuses.contains(status);
        allClosed &= closed;
        lines.add('$id $status ($how)');
      } catch (error) {
        allClosed = false;
        lines.add('$id stopped by ${error.runtimeType}');
      }
    }
    allClosed
        ? log.pass('CLEANUP', title, lines.join('; '))
        : log.fail('CLEANUP', title, lines.join('; '));
  }

  /// The test driver offline (feeder stopped), ALWAYS: in the test's
  /// finally and from the watchdog.
  Future<void> _driverOffline() async {
    const title = 'the test driver is offline';
    if (!peer.api.signedIn) {
      peer.close();
      return log.skip('OFFLINE', title, 'the driver never signed in');
    }
    try {
      final how = await peer.goOffline();
      final detail =
          '$how; fixes sent=${peer.fixesSent} failed=${peer.fixesFailed}';
      peer.onlineStatus == 'offline'
          ? log.pass('OFFLINE', title, detail)
          : log.fail('OFFLINE', title, detail);
    } finally {
      peer.close();
    }
  }

  Future<void> _backHome({required DateTime until}) async {
    for (final key in const [
      'ride-terminal-acknowledge',
      'call-close',
      'ride-completed-done',
      'completion-leave-confirm',
    ]) {
      final f = byKey(key).hitTestable();
      if (tester.any(f)) {
        await tester.tap(f.first, warnIfMissed: false);
        await wait(tester, const Duration(seconds: 2));
      }
    }
    await backToHome(tester);
    final left = until.difference(DateTime.now());
    await pumpUntil(
      tester,
      onHomeOnly,
      timeout: left < const Duration(seconds: 15)
          ? const Duration(seconds: 3)
          : const Duration(seconds: 15),
    );
  }
}
