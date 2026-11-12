part of 'trip_run.dart';

/// Booking through the real screens, the search, and the trip up to the
/// rider on board (G31 rider).
extension _TripBook on TripRun {
  /// The id of the trip the app just booked: its recorded `POST /trips`
  /// answer, else the app's ride session.
  String? _bookedTripId(int from) {
    for (final c in rec.since(from).reversed) {
      if (c.method == 'POST' && c.path == '/api/v1/trips' && c.answer is Map) {
        final id = (c.answer! as Map)['tripId'];
        if (id is String) return id;
      }
    }
    return AppScope.instance.ride.rideId;
  }

  /// Home -> Where to -> drop-off row -> Choose ride (the test driver's
  /// category, cash, wallet first off) -> [scheduled]: date and time ->
  /// Book -> Set pickup -> Confirm. Sets [tripId]; the step says why not.
  Future<void> _book(String id, {bool scheduled = false}) async {
    final title = scheduled
        ? 'rider books a cash ride for later in the app'
        : 'rider books a cash trip in the app';
    tripId = null;
    accepted = false;
    started = false;
    completed = false;
    await backToHome(tester);
    final mark = rec.length;
    final fail = <String>[];

    // ---- Where to -----------------------------------------------------
    final field = find.descendant(
      of: byKey('route-picker-field-destination'),
      matching: find.byType(EditableText),
    );
    await watch.run(
      scheduled ? 'home->schedule' : 'home->route-picker',
      () async {
        if (!await tapKey(
          tester,
          scheduled ? 'home-schedule-later' : 'home-where-to',
        )) {
          return;
        }
        await pumpUntil(
          tester,
          () => shows(find.byType(RoutePickerPage)) && shows(field),
          timeout: const Duration(seconds: 15),
        );
      },
    );
    if (!shows(field)) {
      CheckLog.miss('"route-picker-field-destination" not shown');
      return log.fail(id, title, 'Where to did not open');
    }
    await tester.enterText(field.first, dropoffQuery);
    // The first server suggestion row (`route-picker-row-<i>`; a row equal
    // to a recent place is not drawn, so it is not always row 0).
    final row = byKeyPrefix('route-picker-row-');
    final listed = await pumpUntil(
      tester,
      () => tester.any(row.hitTestable()),
      timeout: const Duration(seconds: 30),
    );
    final auto = calls('/api/v1/locations/autocomplete', from: mark).toList();
    if (!listed) {
      CheckLog.miss('no "route-picker-row-<i>" (server suggestion) shown');
      return log.fail(
        id,
        title,
        'autocomplete: no suggestion row in 30 s; calls='
        '${auto.map((c) => c.status ?? c.error).toList()}',
      );
    }
    await watch.run(
      'route-picker->${scheduled ? 'time' : 'select-ride'}',
      () async {
        await tapHit(tester, row, '"${keysOf(row.hitTestable()).first}"');
        await pumpUntil(
          tester,
          () =>
              shows(find.byType(SelectRide)) ||
              shows(find.byType(ScheduleDateTimeSelector)),
          timeout: const Duration(seconds: 30),
        );
      },
    );

    // ---- the time (booked ride) -----------------------------------------
    if (scheduled) {
      if (!shows(find.byType(ScheduleDateTimeSelector))) {
        CheckLog.miss('ScheduleDateTimeSelector did not open');
        return log.fail(id, title, 'the date and time picker did not open');
      }
      await watch.run('time->select-ride', () async {
        if (!await tapKey(tester, 'schedule-continue')) return;
        await pumpUntil(
          tester,
          () => shows(find.byType(SelectRide)),
          timeout: const Duration(seconds: 30),
        );
      });
    }
    if (!shows(find.byType(SelectRide))) {
      return log.fail(id, title, 'Choose your ride did not open');
    }

    // ---- the category the test driver drives ----------------------------
    final tiles = byKeyPrefix('select-ride-tile-');
    await pumpUntil(
      tester,
      () => shows(tiles) && shows(byKey('select-ride-book')),
      timeout: const Duration(seconds: 30),
    );
    final offered = [
      for (final k in keysOf(tiles)) k.substring('select-ride-tile-'.length),
    ];
    final mine = peer.categoryIds;
    final category = offered.where(mine.contains).firstOrNull;
    if (category == null) {
      return log.fail(
        id,
        title,
        'no ride category of the test driver on Choose your ride '
        '(shown=$offered, driver=${mine.toList()})',
      );
    }
    final tile = byKey('select-ride-tile-$category');
    try {
      await tester.ensureVisible(tile.first);
      await tester.pump(const Duration(milliseconds: 300));
    } catch (_) {}
    if (!await tapHit(tester, tile, '"select-ride-tile-$category"')) {
      fail.add('category tile not tappable');
    }
    await wait(tester, const Duration(seconds: 1));

    // ---- cash, wallet first off -------------------------------------------
    var walletFirstOff = 'no wallet row';
    var cash = false;
    await watch.run('payment-open', () async {
      if (!await tapKey(tester, 'select-ride-payment')) return;
      await pumpUntil(
        tester,
        () => shows(find.byType(PayWithPage)),
        timeout: const Duration(seconds: 10),
      );
    });
    if (shows(find.byType(PayWithPage))) {
      final toggle = byKey('pay-with-wallet-first');
      if (shows(toggle)) {
        final on = (tester.widget(toggle) as SwitchListTile).value;
        if (on) {
          await tapHit(tester, toggle, '"pay-with-wallet-first"');
          await tester.pump(const Duration(milliseconds: 500));
        }
        walletFirstOff =
            shows(toggle) && !(tester.widget(toggle) as SwitchListTile).value
            ? 'off'
            : 'still on';
      }
      await watch.run('payment-close', () async {
        final row = byKey('pay-with-cash');
        try {
          if (shows(row)) await tester.ensureVisible(row.first);
        } catch (_) {}
        cash = await tapHit(tester, row, '"pay-with-cash" (cash payment row)');
        if (!cash) await systemBack(tester);
        await pumpUntil(
          tester,
          () => !shows(find.byType(PayWithPage)),
          timeout: const Duration(seconds: 8),
        );
      });
    } else {
      CheckLog.miss('PayWithPage did not open from "select-ride-payment"');
    }
    if (!cash) fail.add('cash not chosen');

    // ---- Book -> Set pickup -> Confirm -------------------------------------
    await watch.run('select-ride->set-pickup', () async {
      if (!await tapKey(tester, 'select-ride-book')) return;
      await pumpUntil(
        tester,
        () => shows(find.byType(SetPickupPage)),
        timeout: const Duration(seconds: 20),
      );
    });
    if (!shows(find.byType(SetPickupPage))) {
      return log.fail(
        id,
        title,
        'Set pickup did not open after Book; ${fail.join('; ')}',
      );
    }
    final confirm = byKey('set-pickup-confirm');
    await pumpUntil(tester, () {
      if (!tester.any(confirm.hitTestable())) return false;
      return (tester.widget(confirm) as FilledButton).onPressed != null;
    }, timeout: const Duration(seconds: 30));
    await watch.run(
      scheduled ? 'set-pickup->booked' : 'set-pickup->finding',
      () async {
        if (!await tapHit(tester, confirm, '"set-pickup-confirm"')) return;
        await pumpUntil(
          tester,
          () => scheduled
              ? shows(find.byType(RideScheduledPage)) || onHomeOnly()
              : findingShown() || tripScreenShown(),
          timeout: const Duration(seconds: 60),
        );
      },
    );
    final posts = calls('/api/v1/trips', method: 'POST', from: mark).toList();
    final quotes = calls('/api/v1/quotes', method: 'POST', from: mark).toList();
    final made = _bookedTripId(mark);
    if (made == null || !posts.any((c) => c.status != null && !c.failed)) {
      return log.fail(
        id,
        title,
        'POST /trips=${posts.map((c) => c.status ?? c.error).toList()} '
        'quotes=${quotes.map((c) => c.status ?? c.error).toList()}; '
        '${fail.join('; ')}',
      );
    }
    tripId = made;
    booked.add(made);
    final view = await riderView();
    final p = view?['pickup'], d = view?['dropoff'];
    double? n(Object? m, String k) =>
        m is Map && m[k] is num ? (m[k] as num).toDouble() : null;
    if (n(p, 'lat') != null && n(d, 'lat') != null) {
      pickup = (n(p, 'lat')!, n(p, 'lng')!);
      dropoff = (n(d, 'lat')!, n(d, 'lng')!);
    }
    final km = pickup == null || dropoff == null
        ? null
        : DriverPeer.distanceMeters(
                pickup!.$1,
                pickup!.$2,
                dropoff!.$1,
                dropoff!.$2,
              ) /
              1000;
    final checks = <String>[
      ...fail,
      if (view?['paymentMethod'] != 'cash')
        'server payment ${view?['paymentMethod']} (want cash)',
      if (view?['categoryId'] != category)
        'server category ${view?['categoryId']} (chosen $category)',
      if (km == null) 'server trip has no pickup/drop-off points',
      if (km != null && (km < 0.3 || km > 5))
        'drop-off ${km.toStringAsFixed(1)} km from the pickup (want 0.3-5)',
      if (!scheduled && !findingShown() && !tripScreenShown())
        'Finding did not show',
    ];
    final detail =
        'trip $made ${view?['status']} category=$category quotes='
        '${quotes.map((c) => c.status).toList()} POST /trips='
        '${posts.map((c) => c.status).toList()} cash=$cash wallet first='
        '$walletFirstOff route ${km?.toStringAsFixed(1)} km fare='
        '${moneyOf(view?['fare'])}';
    checks.isEmpty
        ? log.pass(id, title, detail)
        : log.fail(id, title, '${checks.join('; ')}; $detail');
  }

  /// Finding on screen, the emergency numbers the kit lists while no
  /// driver has the trip (SOS-FINDING), and the offer reaching the test
  /// driver (polled over HTTP meanwhile), who accepts it.
  Future<void> _searching() async {
    const title = 'Finding shows; the offer goes to the test driver';
    final id = tripId!;
    var offerDone = false;
    final offerWait = peer
        .waitOffer(id, const Duration(seconds: 90), stop: () => stopped)
        .whenComplete(() => offerDone = true);
    final steps = keysOf(byKeyPrefix('search-step-'));
    final map = shows(byKey('finding-map'));
    await _sosOnFinding();
    await pumpUntil(
      tester,
      () => offerDone,
      timeout: const Duration(seconds: 95),
    );
    final (offer, others) = await offerWait;
    final view = await riderView();
    if (offer == null) {
      log.fail(
        'SEARCHING',
        title,
        'no offer for this trip to the test driver in 90 s; server '
            '${view?['status']}; offered to the driver meanwhile: '
            '${others.isEmpty ? 'nothing' : '${others.length} other trip(s)'} '
            '(Finding map=$map steps=${steps.length})',
      );
      return log.skip(
        'DRIVER-FOUND',
        'rider sees the driver',
        'not run: no offer',
      );
    }
    log.pass(
      'SEARCHING',
      title,
      'offer ${offer['offerId']} to the test driver; Finding map=$map '
          'steps=${steps.length} server=${view?['status']}',
    );
    const found = 'rider sees the driver (UI-LAG)';
    final version = offer['version'];
    final answer = await peer.api.acceptOffer(
      offer['offerId'] as String,
      version is num ? version.toInt() : 1,
    );
    if (!answer.ok) {
      return log.fail('DRIVER-FOUND', found, 'driver accept ${answer.short}');
    }
    peer.tripId = id;
    int? took;
    await watch.run('finding->driver-found', () async {
      took = await waitStage(
        tester,
        stageFor['accepted']!,
        timeout: TripRun.stageWait,
        extra: () => tripScreenShown() && shows(byKey('waiting-panel')),
      );
    });
    var status = (await riderView())?['status'] as String?;
    if (status == 'accepted') {
      final head = await peer.step(id, 'head-to-pickup', {
        'location': geoFix(peer.lat, peer.lng),
      });
      CheckLog.say('STEP driver head-to-pickup ${head.short}');
      status = await waitStatus({
        'driver_to_pickup',
      }, const Duration(seconds: 10));
    }
    accepted = status == 'accepted' || status == 'driver_to_pickup';
    final (lagOk, lagText) = lag(took);
    final detail =
        'driver accept ${answer.short}; rider trip screen=${tripScreenShown()} '
        'stage=${riderStage()} server=$status; $lagText';
    accepted && tripScreenShown() && lagOk
        ? log.pass('DRIVER-FOUND', found, detail)
        : log.fail('DRIVER-FOUND', found, detail);
    if (tripScreenShown()) await log.screenshot(tester, 'trip-driver-found');
  }

  /// The driver drives to the pickup; the rider's map is kept, the stage
  /// is "arriving" and the ETA text moves (reported).
  Future<void> _arriving() async {
    const title = 'driver on the way: stage, map kept, ETA moves';
    final to = pickup ?? (lat, lng);
    final etas = <String>{};
    void sampleEta() {
      for (final t in textsUnder(byKey('waiting-panel'))) {
        if (RegExp(r'\d+\s*min').hasMatch(t)) etas.add(t);
      }
    }

    final before = watch.mapStates()['trip'];
    await watch.run('arriving', () async {
      // Stop ~40 m short: the arrive below sends the pickup point itself.
      final near = DriverPeer.offset(to.$1, to.$2, north: -30, east: -25);
      await peer.driveTo(near.$1, near.$2, (d) async {
        sampleEta();
        await rideCheckGate();
        await wait(tester, d);
      });
      sampleEta();
    });
    final after = watch.mapStates()['trip'];
    final stage = riderStage();
    final status = (await riderView())?['status'];
    final kept =
        before != null &&
        after != null &&
        before.intersection(after).isNotEmpty;
    final detail =
        'stage=$stage server=$status trip map kept=$kept ETA texts seen='
        '${etas.length} (${etas.length > 1 ? 'moved' : 'did not move: reported'}); '
        'fixes sent=${peer.fixesSent} failed=${peer.fixesFailed}';
    stageFor['driver_to_pickup']!.contains(stage) && kept && tripScreenShown()
        ? log.pass('ARRIVING', title, detail)
        : log.fail('ARRIVING', title, detail);
  }

  /// The driver taps Arrived (HTTP, at the pickup); the rider sees the
  /// arrived stage and the PIN card.
  Future<void> _arrived() async {
    const title = 'arrived: the rider sees the PIN (UI-LAG)';
    final id = tripId!;
    final to = pickup ?? (lat, lng);
    peer
      ..lat = to.$1
      ..lng = to.$2;
    final answer = await peer.step(id, 'arrive', {
      'location': geoFix(to.$1, to.$2),
    });
    if (!answer.ok) {
      return log.fail('ARRIVED', title, 'driver arrive ${answer.short}');
    }
    int? took;
    await watch.run('arrived', () async {
      took = await waitStage(
        tester,
        stageFor['arrived']!,
        timeout: TripRun.stageWait,
        extra: () => shows(byKey('trip-pin-card')),
      );
      await pumpUntil(
        tester,
        () => shows(byKey('trip-pin-card')),
        timeout: const Duration(seconds: 8),
      );
    });
    final view = await riderView();
    final pinNeeded = view?['pinRequired'] == true;
    final pinCard = shows(byKey('trip-pin-card'));
    // The arrived sheet: "I'm on my way" (the rider's answer).
    final onWay = byKey('driver-arrived-on-way');
    if (tester.any(onWay.hitTestable())) {
      await watch.run('arrived-sheet-close', () async {
        await tapHit(tester, onWay, '"driver-arrived-on-way"');
        await pumpUntil(
          tester,
          () => !shows(onWay),
          timeout: const Duration(seconds: 8),
        );
      });
    }
    final (lagOk, lagText) = lag(took);
    final detail =
        'driver arrive ${answer.short}; server=${view?['status']} '
        'pinRequired=$pinNeeded PIN card=$pinCard stage=${riderStage()}; $lagText';
    view?['status'] == 'arrived' && (!pinNeeded || pinCard) && lagOk
        ? log.pass('ARRIVED', title, detail)
        : log.fail('ARRIVED', title, detail);
  }

  /// The PIN the rider sees = the server's; the driver sends it, boards
  /// and starts; the rider's in-trip panel shows.
  Future<void> _pin() async {
    const title = 'PIN on screen = server, trip starts (UI-LAG)';
    final id = tripId!;
    final onScreen = pinShown();
    refreshRiderToken();
    final served = await riderApi.get(
      '/api/v1/trips/${Uri.encodeComponent(id)}/pin',
    );
    final serverPin =
        (served.map?['pin'] ?? lastRiderView?['pickupPin']) as String?;
    // The driver app's way (live_trip_commands.dart start): the PIN is
    // verified first, then board and start from the version it returns.
    final steps = <String>[];
    final pin = serverPin ?? onScreen;
    if (pin != null && lastRiderView?['pinRequired'] == true) {
      final v = await peer.api.verifyPin(id, pin);
      steps.add('verify ${v.short}');
    }
    final board = await peer.step(id, 'board');
    steps.add('board ${board.short}');
    final start = await peer.step(id, 'start');
    steps.add('start ${start.short}');
    int? took;
    await watch.run('in-trip', () async {
      took = await waitStage(
        tester,
        stageFor['in_trip']!,
        timeout: TripRun.stageWait,
        extra: () => shows(byKey('trip-summary-line')),
      );
    });
    final status = await waitStatus(
      onBoardStatuses,
      const Duration(seconds: 5),
    );
    started = onBoardStatuses.contains(status);
    if (started) onBoardAt = DateTime.now();
    final pinOk =
        lastRiderView?['pinRequired'] != true ||
        (onScreen != null && onScreen == serverPin);
    final (lagOk, lagText) = lag(took);
    final detail =
        'PIN on screen=${onScreen != null} same as server=${onScreen != null && onScreen == serverPin} '
        '(GET /pin ${served.short}); driver ${steps.join(', ')}; server=$status '
        'in-trip panel=${shows(byKey('trip-summary-line'))} stage=${riderStage()}; $lagText';
    started && pinOk && lagOk
        ? log.pass('PIN', title, detail)
        : log.fail('PIN', title, detail);
    if (started) await log.screenshot(tester, 'trip-in-trip');
  }

  /// Background and back: the same trip screen, the same map, the same
  /// server status. Run 6 lesson: NEVER pump while hidden/paused.
  Future<void> _switch(String n) async {
    final id = 'SWITCH-$n';
    const title = 'background/resume keeps the trip';
    if (late) return log.skip(id, title, 'not run: time limit near');
    final before = (await riderView())?['status'];
    final mapBefore = watch.mapStates()['trip'];
    await watch.run('background-resume-$n', () async {
      final binding = tester.binding;
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump(const Duration(milliseconds: 300));
      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      CheckLog.say('STEP background (frames off, no pump) 3 s');
      await Future<void>.delayed(const Duration(seconds: 3));
      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      CheckLog.say('STEP resumed (frames on)');
      await tester.pump(const Duration(milliseconds: 300));
      await wait(tester, const Duration(seconds: 3));
    });
    await rideCheckGate();
    final after = (await riderView())?['status'];
    final mapAfter = watch.mapStates()['trip'];
    final sameMap =
        mapBefore != null &&
        mapAfter != null &&
        mapBefore.intersection(mapAfter).isNotEmpty;
    final detail =
        'trip screen on top=${onTripTop()} same map=$sameMap server '
        'before=$before after=$after stage=${riderStage()}';
    onTripTop() && sameMap && before == after
        ? log.pass(id, title, detail)
        : log.fail(id, title, detail);
  }
}
