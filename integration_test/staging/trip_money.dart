part of 'trip_run.dart';

/// The money and after-trip checks, rider app on the phone (G31 rider):
/// the in-trip "ride · Cash price" line, the completed screen's amount
/// and G33 "Pay the driver {amount} in the car" (owner 2026-11-12 ~16:45
/// UTC: the amount equals the driver's collect screen = complete-preview
/// cashDue), rating, receipt and history against the server. A server
/// field that is missing is a FAIL, never a pass.
extension _TripMoney on TripRun {
  (int, String)? _cashDue() => moneyOf(preview?['cashDue']);

  /// PAY-IN-CAR (during the trip): the summary line names cash and the
  /// trip's fare as the server booked it.
  Future<void> _payInCarLine() async {
    const title = 'in-trip line: cash and the fare = server';
    final line = textOf('trip-summary-line');
    final view = await riderView();
    final fare = moneyOf(view?['fare']);
    final cashWord = L10n.current.payCash;
    final hasCash = line != null && line.contains(cashWord);
    final hasFare = line != null && TripRun.hasMoney([line], fare);
    final detail =
        'line shown=${line != null} cash word "$cashWord"=$hasCash fare '
        '${TripRun.shown(fare)} on it=$hasFare server payment='
        '${view?['paymentMethod']}';
    line != null && hasCash && hasFare && view?['paymentMethod'] == 'cash'
        ? log.pass('PAY-IN-CAR', title, detail)
        : log.fail('PAY-IN-CAR', title, detail);
  }

  Future<void> _dropoff() async {
    const title = 'driver drives to the drop-off, trip still running';
    final to = dropoff;
    if (to == null) {
      return log.fail('DROPOFF', title, 'server trip had no drop-off point');
    }
    final before = watch.mapStates()['trip'];
    await watch.run('to-dropoff', () async {
      await peer.driveTo(to.$1, to.$2, (d) async {
        await rideCheckGate();
        await wait(tester, d);
      }, metersPerSecond: 15);
      await wait(tester, const Duration(seconds: 3));
    });
    final after = watch.mapStates()['trip'];
    final status = await waitStatus(
      onBoardStatuses,
      const Duration(seconds: 5),
    );
    final kept =
        before != null &&
        after != null &&
        before.intersection(after).isNotEmpty;
    final detail =
        'server=$status stage=${riderStage()} trip screen=${tripScreenShown()} '
        'map kept=$kept fixes sent=${peer.fixesSent} failed=${peer.fixesFailed}';
    onBoardStatuses.contains(status) && tripScreenShown() && kept
        ? log.pass('DROPOFF', title, detail)
        : log.fail('DROPOFF', title, detail);
  }

  /// The driver completes with the cash it collects (complete-preview
  /// cashDue); the rider's completed screen shows the amount and the G33
  /// line "Pay the driver {cashDue} in the car".
  Future<void> _pay() async {
    const title =
        'completed: amount, "Pay the driver ... in the car" = cashDue';
    final id = tripId!;
    final p = await peer.api.completePreview(id);
    preview = p.map;
    final due = _cashDue();
    final total = moneyOf(preview?['total']);
    if (!p.ok || due == null || total == null) {
      return log.fail(
        'PAY',
        title,
        'complete-preview ${p.short} cashDue=$due total=$total',
      );
    }
    final done = await peer.step(id, 'complete', {
      'previewId': preview?['previewId'],
      'cashCollected': preview?['cashDue'],
    });
    int? took;
    await watch.run('completed', () async {
      final t0 = DateTime.now();
      final seen = await pumpUntil(
        tester,
        completedShown,
        timeout: TripRun.stageWait,
      );
      took = seen ? DateTime.now().difference(t0).inSeconds : null;
      await pumpUntil(
        tester,
        () => shows(byKey('completion-pay-in-car')),
        timeout: const Duration(seconds: 10),
      );
    });
    final status = await waitStatus({'completed'}, const Duration(seconds: 10));
    completed = status == 'completed';
    final hero = textOf('completion-hero-amount');
    final payLine = textOf('completion-pay-in-car');
    final want = L10n.current.payDriverInCar(TripRun.shown(due)!);
    final (lagOk, lagText) = lag(took);
    final problems = <String>[
      if (!done.ok) 'driver complete ${done.short}',
      if (!completed) 'server $status',
      if (!completedShown()) 'completed screen not shown',
      if (payLine == null) 'no "completion-pay-in-car" line (G33)',
      if (payLine != null && payLine != want)
        'G33 line differs from the driver collect amount ${TripRun.shown(due)}',
      if (hero == null) 'no "completion-hero-amount"',
      if (hero != null && !TripRun.hasMoney([hero], total))
        'hero amount is not the total ${TripRun.shown(total)}',
      if (!lagOk) lagText,
    ];
    final detail =
        'driver collects ${TripRun.shown(due)} (complete ${done.short}); '
        'total ${TripRun.shown(total)}; hero="$hero" G33 line equal=${payLine == want}; '
        'server=$status earlyEnd=${preview?['earlyEnd']}; $lagText';
    problems.isEmpty
        ? log.pass('PAY', title, detail)
        : log.fail('PAY', title, 'problems: ${problems.join('; ')}; $detail');
    if (completedShown()) await log.screenshot(tester, 'ride-completed');
  }

  Future<void> _rate() async {
    const title = 'stars + Done send the rating, Home shows';
    final id = tripId!;
    var tapped = false;
    await watch.run('rate', () async {
      tapped = await tapKey(tester, 'rating-star-5');
      await tester.pump(const Duration(milliseconds: 500));
    });
    final mark = rec.length;
    await watch.run('done->home', () async {
      await tapKey(tester, 'ride-completed-done');
      await pumpUntil(tester, onHomeOnly, timeout: const Duration(seconds: 30));
    });
    final posts = calls(
      '/api/v1/trips/$id/rating',
      method: 'POST',
      from: mark,
    ).map((c) => c.status ?? c.error).toList();
    final driverRates = await peer.api.rate(id, 5);
    final detail =
        'star tapped=$tapped rating POST=$posts Home alone=${onHomeOnly()}; '
        'driver rates the rider ${driverRates.short}';
    tapped && posts.any((s) => s is int && s < 300) && onHomeOnly()
        ? log.pass('RATE', title, detail)
        : log.fail('RATE', title, detail);
  }

  /// The rider's receipt: total = the completed price, cashPaid = the
  /// cash the driver collected (409 while it is being written: retried).
  Future<void> _receipt() async {
    const title = 'receipt: total and cash paid = what was paid';
    final id = tripId!;
    refreshRiderToken();
    var receipt = await riderApi.receipt(id);
    final end = DateTime.now().add(const Duration(seconds: 30));
    while (receipt.status == 409 && DateTime.now().isBefore(end) && !stopped) {
      await wait(tester, const Duration(seconds: 3));
      receipt = await riderApi.receipt(id);
    }
    final total = moneyOf(receipt.map?['total']);
    final cashPaid = moneyOf(receipt.map?['cashPaid']);
    final want = moneyOf(preview?['total']);
    final due = _cashDue();
    final detail =
        'receipt ${receipt.short} total=${TripRun.shown(total)} (completed '
        '${TripRun.shown(want)}) cashPaid=${TripRun.shown(cashPaid)} (collected '
        '${TripRun.shown(due)}) debt=${moneyOf(receipt.map?['debtIncluded'])}';
    receipt.ok && total != null && total == want && cashPaid == due
        ? log.pass('RECEIPT', title, detail)
        : log.fail('RECEIPT', title, detail);
  }

  /// Menu -> Ride history -> Completed -> the trip -> its detail (price
  /// and the server receipt's total) -> back to Home.
  Future<void> _history() async {
    const title = 'history: the trip, its price and receipt = server';
    if (late) return log.skip('HISTORY', title, 'not run: time limit near');
    final id = tripId!;
    await backToHome(tester);
    await watch.run('home->menu', () async {
      if (!await tapKey(tester, 'home-menu')) return;
      await pumpUntil(
        tester,
        () => shows(find.byType(RiderMenuPage)),
        timeout: const Duration(seconds: 8),
      );
    });
    var opened = false;
    await watch.run('menu->history', () async {
      final tile = byKey('menu-ride-history');
      if (shows(tile)) {
        try {
          await tester.ensureVisible(tile.first);
        } catch (_) {}
      }
      if (!await tapHit(tester, tile, '"menu-ride-history"')) return;
      opened = await pumpUntil(
        tester,
        () => shows(find.byType(RideHistory)),
        timeout: const Duration(seconds: 10),
      );
    });
    final tab = find.descendant(
      of: find.byType(RideHistory),
      matching: find.text(L10n.current.resCompleted),
    );
    if (opened) await tapHit(tester, tab, 'Ride History tab "Completed"');
    final row = byKey('history-ride-$id');
    final listed = await pumpUntil(
      tester,
      () => shows(row),
      timeout: const Duration(seconds: 20),
    );
    String? price;
    String? receiptTotal;
    if (listed) {
      await watch.run('history->detail', () async {
        try {
          await tester.ensureVisible(row.first);
        } catch (_) {}
        await tapHit(tester, row, '"history-ride-$id"');
        await pumpUntil(
          tester,
          () => shows(byKey('history-detail-price')),
          timeout: const Duration(seconds: 10),
        );
        await pumpUntil(
          tester,
          () => shows(byKey('receipt-total')),
          timeout: const Duration(seconds: 15),
        );
      });
      price = textOf('history-detail-price');
      receiptTotal = textOf('receipt-total');
    } else {
      CheckLog.miss('"history-ride-$id" not listed on Completed');
    }
    await watch.run('history->home', () => backToHome(tester, tries: 5));
    final total = moneyOf(preview?['total']);
    final priceOk = price != null && TripRun.hasMoney([price], total);
    final receiptOk =
        receiptTotal != null && TripRun.hasMoney([receiptTotal], total);
    final detail =
        'page=$opened trip listed=$listed price line has '
        '${TripRun.shown(total)}=$priceOk receipt total=$receiptOk; '
        'Home alone=${onHomeOnly()}';
    opened && listed && priceOk && receiptOk && onHomeOnly()
        ? log.pass('HISTORY', title, detail)
        : log.fail('HISTORY', title, detail);
  }
}
