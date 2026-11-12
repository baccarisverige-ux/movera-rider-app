part of 'trip_run.dart';

/// Owner 2026-11-12 ~15:40 UTC ("Also the schedule ride"), rider app on the
/// phone (G31 rider): the `trip-scheduled` scenario. The rider books for
/// later in the app (Book for later -> Where to -> the earliest slot the
/// app offers -> category, cash -> Set pickup); the driver (HTTP) accepts
/// it from `GET /driver/reservations`; the rider's Home card and its page
/// show it; the rider cancels ride A in the app; ride B is started by the
/// driver ("leave now", `POST /driver/reservations/{id}/start`) and runs
/// the trip steps without chat, calls, SOS and ride check (time).
///
/// The driver never cancels a booked ride: late cancels count to the
/// test driver's late-cancel limit (pause). Clean-up = rider cancel only.
extension _TripScheduled on TripRun {
  Future<void> _scheduledScenario() async {
    // ---- A: book, driver accepts, the rider cancels in the app ---------
    await step(
      'SCHED-CANCEL-BOOK',
      'rider books ride A for later in the app',
      () => _bookLater('SCHED-CANCEL-BOOK'),
    );
    if (tripId != null) {
      await step(
        'SCHED-CANCEL-ACCEPT',
        'driver accepts ride A; the rider sees the driver',
        () => _acceptBooked('SCHED-CANCEL-ACCEPT'),
      );
      await step(
        'SCHED-CANCEL',
        'rider cancels ride A in the app',
        _cancelBooked,
      );
    }

    // ---- B: the full booked ride ------------------------------------------
    if (late) {
      return log.skip(
        'SCHED-BOOK',
        'booked ride B',
        'not run: time limit near',
      );
    }
    await step(
      'SCHED-BOOK',
      'rider books ride B for later in the app',
      () => _bookLater('SCHED-BOOK'),
    );
    if (tripId == null) return;
    await step(
      'SCHED-ACCEPT',
      'driver accepts ride B; the rider sees the driver',
      () => _acceptBooked('SCHED-ACCEPT'),
    );
    if (!accepted) return;
    await step('SCHED-LIST', 'Home card and its page = server', _scheduledCard);
    await step('SCHED-REMINDER', 'pickup reminder notice', _reminder);
    await step('SCHED-LEAVE', 'driver leaves now: live trip opens', _leave);
    if (!accepted) return;
    await _tripSteps(extras: false);
  }

  /// [TripRun._book] in the booked-for-later way, then Done on "Your ride
  /// is scheduled" back to Home.
  Future<void> _bookLater(String id) async {
    await _book(id, scheduled: true);
    await watch.run('$id:scheduled->home', () async {
      if (shows(find.byType(RideScheduledPage))) {
        await tapKey(tester, 'reservation-scheduled-done');
      }
      await pumpUntil(tester, onHomeOnly, timeout: const Duration(seconds: 15));
    });
  }

  /// The Home card of [trip]: `home-reservation-<tripId>`.
  Finder _homeCard(String trip) => byKey('home-reservation-$trip');

  /// The driver accepts the booked ride from his open list; the rider's
  /// card page then shows the driver.
  Future<void> _acceptBooked(String id) async {
    const title = 'driver accepts the booked ride; the rider sees the driver';
    accepted = false;
    final trip = tripId!;
    Map<String, dynamic>? item;
    final end = DateTime.now().add(const Duration(seconds: 60));
    var lastList = '';
    while (item == null && DateTime.now().isBefore(end) && !stopped) {
      final page = await peer.api.reservations('open');
      lastList = page.short;
      final items = page.map?['items'];
      if (items is List) {
        item = items
            .whereType<Map>()
            .map(Map<String, dynamic>.from)
            .where((r) => r['tripId'] == trip)
            .firstOrNull;
      }
      if (item == null) await wait(tester, const Duration(seconds: 3));
    }
    if (item == null) {
      return log.fail(
        id,
        title,
        'not in the driver\'s open booked rides in 60 s (last list $lastList; '
        'listTo/listNearKm rules may keep it from the test driver)',
      );
    }
    final answer = await peer.api.acceptReservation(
      trip,
      (item['version'] as num?)?.toInt() ?? 1,
    );
    if (!answer.ok) {
      return log.fail(id, title, 'driver accept ${answer.short}');
    }
    var page = false;
    int? took;
    await watch.run('$id:home->upcoming', () async {
      await backToHome(tester);
      final card = _homeCard(trip);
      if (!await pumpUntil(
        tester,
        () => tester.any(card.hitTestable()),
        timeout: const Duration(seconds: 15),
      )) {
        CheckLog.miss(
          '"home-reservation-$trip" not tappable on Home '
          '(cards: ${keysOf(byKeyPrefix('home-reservation-'))})',
        );
        return;
      }
      await tapHit(tester, card, '"home-reservation-$trip"');
      page = await pumpUntil(
        tester,
        () => shows(find.byType(UpcomingReservationPage)),
        timeout: const Duration(seconds: 10),
      );
      final t0 = DateTime.now();
      final seen = await pumpUntil(
        tester,
        () => shows(byKey('reservation-driver-card')),
        timeout: TripRun.stageWait,
      );
      took = seen ? DateTime.now().difference(t0).inSeconds : null;
    });
    final status = (await riderView())?['status'];
    accepted = answer.ok && status == 'accepted';
    final (lagOk, lagText) = lag(took);
    final detail =
        'driver accept ${answer.short}; server=$status card page=$page '
        'driver card=${shows(byKey('reservation-driver-card'))}; $lagText';
    accepted && page && took != null && lagOk
        ? log.pass(id, title, detail)
        : log.fail(id, title, detail);
  }

  /// On the open card page: Cancel -> confirm (the fee note shows what it
  /// costs) -> a reason -> submit. The server says cancelled_by_rider and
  /// the Home card is gone.
  Future<void> _cancelBooked() async {
    const title = 'rider cancels the booked ride in the app';
    final trip = tripId!;
    if (!shows(find.byType(UpcomingReservationPage))) {
      await backToHome(tester);
      if (tester.any(_homeCard(trip).hitTestable())) {
        await tapHit(tester, _homeCard(trip), '"home-reservation-$trip"');
        await pumpUntil(
          tester,
          () => shows(find.byType(UpcomingReservationPage)),
          timeout: const Duration(seconds: 10),
        );
      }
    }
    final mark = rec.length;
    String? feeNote;
    var submitted = false;
    await watch.run('sched-cancel', () async {
      if (!await tapKey(tester, 'reservation-cancel')) return;
      if (!await pumpUntil(
        tester,
        () => shows(byKey('reservation-cancel-confirm')),
        timeout: const Duration(seconds: 8),
      )) {
        CheckLog.miss('"reservation-cancel-confirm" sheet did not open');
        return;
      }
      feeNote = shows(byKey('reservation-cancel-fee'))
          ? 'fee'
          : shows(byKey('reservation-cancel-free'))
          ? 'free'
          : null;
      await tapKey(tester, 'reservation-cancel-confirm');
      final reasons = byKeyPrefix('cancel-reason-');
      await pumpUntil(
        tester,
        () => keysOf(reasons).any((k) => k != 'cancel-reason-submit'),
        timeout: const Duration(seconds: 8),
      );
      final first = keysOf(reasons).where((k) => k != 'cancel-reason-submit');
      if (first.isEmpty) {
        CheckLog.miss('no "cancel-reason-<id>" row on the reason sheet');
        return;
      }
      await tapKey(tester, first.first);
      submitted = await tapKey(tester, 'cancel-reason-submit');
      await pumpUntil(
        tester,
        () => callsMatching(
          RegExp(r'/cancel$'),
          method: 'POST',
          from: mark,
        ).any((c) => c.status != null || c.error != null),
        timeout: const Duration(seconds: 20),
      );
      await wait(tester, const Duration(seconds: 2));
      await backToHome(tester);
    });
    final posts = callsMatching(
      RegExp(r'/cancel$'),
      method: 'POST',
      from: mark,
    ).map((c) => c.status ?? c.error).toList();
    final view = await riderView();
    final c = view?['cancellation'];
    final fee = c is Map ? moneyOf(c['fee']) : null;
    await pumpUntil(
      tester,
      () => !shows(_homeCard(trip)),
      timeout: const Duration(seconds: 10),
    );
    final gone = !shows(_homeCard(trip));
    final detail =
        'note=$feeNote submitted=$submitted cancel POST=$posts server='
        '${view?['status']} fee=${TripRun.shown(fee) ?? 'none'} '
        '(note ${fee != null && fee.$1 > 0 ? 'must say fee' : 'free'}); '
        'Home card gone=$gone';
    final noteOk = fee == null || fee.$1 == 0
        ? feeNote != null
        : feeNote == 'fee';
    view?['status'] == 'cancelled_by_rider' && submitted && gone && noteOk
        ? log.pass('SCHED-CANCEL', title, detail)
        : log.fail('SCHED-CANCEL', title, detail);
    tripId = null;
  }

  /// The Home card and its page: the pickup time = the server's
  /// scheduledAt (local HH:MM).
  Future<void> _scheduledCard() async {
    const title = 'Home card and its page: pickup time = server';
    final trip = tripId!;
    final view = await riderView();
    final at = DateTime.tryParse('${view?['scheduledAt']}')?.toLocal();
    final hhmm = at == null
        ? null
        : '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    var page = shows(find.byType(UpcomingReservationPage));
    if (!page) {
      await watch.run('sched-list', () async {
        await backToHome(tester);
        if (tester.any(_homeCard(trip).hitTestable())) {
          await tapHit(tester, _homeCard(trip), '"home-reservation-$trip"');
        }
        page = await pumpUntil(
          tester,
          () => shows(find.byType(UpcomingReservationPage)),
          timeout: const Duration(seconds: 10),
        );
      });
    }
    final texts = textsUnder(find.byType(UpcomingReservationPage));
    final timeShown = hhmm != null && texts.any((t) => t.contains(hhmm));
    await backToHome(tester);
    final cardOnHome = shows(_homeCard(trip));
    final detail =
        'card on Home=$cardOnHome page=$page pickup $hhmm shown=$timeShown '
        'server=${view?['status']}';
    cardOnHome && page && timeShown
        ? log.pass('SCHED-LIST', title, detail)
        : log.fail('SCHED-LIST', title, detail);
  }

  Future<void> _reminder() async {
    const title = 'pickup reminder notice';
    final config = rec.lastAnswer['/api/v1/rider/config'];
    final res = config is Map ? config['reservations'] : null;
    log.skip(
      'SCHED-REMINDER',
      title,
      'NOT CHECKED: the rider reminder comes riderReminderMin before the '
          'pickup (zone reservations ${res is Map ? res['riderReminderMin'] : 'not read'}), '
          'longer than the earliest booking the app allows (now + 30 min)',
    );
  }

  /// The driver starts the booked ride (`POST /driver/reservations/{id}/
  /// start`, allowed from scheduledAt - onlineBeforeMin): the rider's live
  /// trip screen opens.
  Future<void> _leave() async {
    const title = 'driver leaves now: the rider\'s live trip opens';
    accepted = false;
    final trip = tripId!;
    final view = await peer.trip(trip);
    final start = await peer.api.startReservation(
      trip,
      (view?['version'] as num?)?.toInt() ?? 1,
    );
    peer.tripId = trip;
    int? took;
    await watch.run('sched-leave', () async {
      await backToHome(tester);
      final t0 = DateTime.now();
      final seen = await pumpUntil(
        tester,
        () => tripScreenShown(),
        timeout: TripRun.stageWait,
      );
      took = seen ? DateTime.now().difference(t0).inSeconds : null;
    });
    final status = await waitStatus({
      'driver_to_pickup',
    }, const Duration(seconds: 15));
    accepted = start.ok && status == 'driver_to_pickup';
    final (lagOk, lagText) = lag(took);
    final detail =
        'driver start ${start.short}; server=$status rider trip screen='
        '${tripScreenShown()} stage=${riderStage()}; $lagText';
    accepted && tripScreenShown() && lagOk
        ? log.pass('SCHED-LEAVE', title, detail)
        : log.fail('SCHED-LEAVE', title, detail);
  }
}
