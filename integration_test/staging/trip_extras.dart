part of 'trip_run.dart';

/// The checks around the trip's main steps (owner 2026-11-12: chat both
/// ways, call states, SOS numbers per zone, ride check), rider app on the
/// phone (G31 rider).
extension _TripExtras on TripRun {
  /// SOS-ZONES (no screen): every zone of `GET /rider/zones` sends a list
  /// of emergency numbers the app takes (`EmergencyNumbers.parse`).
  Future<void> _sosZones() async {
    const title = 'every zone sends emergency numbers';
    final (status, zones) = await ask('/api/v1/rider/zones');
    final items = zones is Map ? zones['items'] ?? zones['zones'] : zones;
    final ids = <String>[
      if (items is List)
        for (final z in items)
          if (z is Map && (z['zoneId'] ?? z['id']) is String)
            (z['zoneId'] ?? z['id']) as String,
    ];
    if (ids.isEmpty) {
      return log.fail(
        'SOS-ZONES',
        title,
        'GET /rider/zones $status: no zone ids',
      );
    }
    final empty = <String>[];
    final counts = <String>[];
    for (final zone in ids.take(20)) {
      final (s, config) = await ask('/api/v1/rider/config', {'zoneId': zone});
      final rows = EmergencyNumbers.parse(
        config is Map ? config['emergencyNumbers'] : null,
      );
      if (rows == null) {
        empty.add('$zone ($s)');
      } else {
        counts.add('$zone=${rows.map((r) => r.number).join('/')}');
      }
    }
    final detail =
        'zones=${ids.length} with numbers: ${counts.join(', ')}'
        '${empty.isEmpty ? '' : '; NONE: ${empty.join(', ')}'}';
    empty.isEmpty
        ? log.pass('SOS-ZONES', title, detail)
        : log.fail('SOS-ZONES', title, detail);
  }

  /// The server's emergency numbers for the trip's zone.
  Future<(int, List<String>)> _zoneNumbers() async {
    final zone =
        (lastRiderView?['zoneId'] ?? (await riderView())?['zoneId']) as String?;
    if (zone == null) return (0, const <String>[]);
    final (status, config) = await ask('/api/v1/rider/config', {
      'zoneId': zone,
    });
    final rows = EmergencyNumbers.parse(
      config is Map ? config['emergencyNumbers'] : null,
    );
    return (status, <String>[for (final r in rows ?? const []) r.number]);
  }

  /// SOS-FINDING: while no driver has the trip the kit lists one call row
  /// per emergency number of the zone (`safety-call-<number>`), on screen.
  Future<void> _sosOnFinding() async {
    const title = 'kit rows while finding = the zone numbers';
    if (!findingShown()) {
      return log.skip('SOS-FINDING', title, 'NOT CHECKED: Finding not shown');
    }
    final (status, served) = await _zoneNumbers();
    var opened = false;
    await watch.run('safety-open-finding', () async {
      final button = byKey('trip-safety-button').hitTestable();
      if (tester.any(button)) {
        await tester.tap(button.first, warnIfMissed: false);
      } else {
        CheckLog.miss('"trip-safety-button" not tappable on Finding');
      }
      opened = await pumpUntil(
        tester,
        safetyKitOpen,
        timeout: const Duration(seconds: 6),
      );
    });
    final rows = [
      for (final k in keysOf(byKeyPrefix('safety-call-')))
        k.substring('safety-call-'.length),
    ];
    final sos = shows(byKey('safety-sos'));
    if (opened) await log.screenshot(tester, 'finding-safety');
    await watch.run('safety-close-finding', () async {
      if (safetyKitOpen()) await systemBack(tester);
      await pumpUntil(
        tester,
        () => !safetyKitOpen(),
        timeout: const Duration(seconds: 5),
      );
    });
    final detail =
        'kit opened=$opened rows on screen=$rows server (config $status)='
        '$served SOS button=$sos (none expected before a driver)';
    opened && served.isNotEmpty && rows.join(',') == served.join(',')
        ? log.pass('SOS-FINDING', title, detail)
        : log.fail('SOS-FINDING', title, detail);
  }

  /// Driver -> rider (badge, then the text in the chat), rider -> driver
  /// (typed in the app, read over HTTP), driver -> rider while open.
  Future<void> _chat() async {
    const title = 'chat both ways, unread badge';
    if (late) return log.skip('CHAT', title, 'not run: time limit near');
    final id = tripId!;
    final first = 'TL driver ping ${TripRun.randomTag()}';
    final sent1 = await peer.api.sendMessage(id, first);
    final t0 = DateTime.now();
    final badge = await pumpUntil(
      tester,
      () => chatUnread() > 0,
      timeout: TripRun.stageWait,
    );
    final badgeLag = badge ? DateTime.now().difference(t0).inSeconds : null;
    final opened = await watch.run('chat-open', () async {
      await tapOnSheet(tester, 'waiting-chat');
      return pumpUntil(tester, chatOpen, timeout: const Duration(seconds: 10));
    });
    final seen1 = await pumpUntil(
      tester,
      () => shows(find.text(first)),
      timeout: const Duration(seconds: 15),
    );
    final reply = 'TL rider reply ${TripRun.randomTag()}';
    final mark = rec.length;
    var typed = false;
    if (opened && shows(chatField())) {
      await tester.enterText(chatField().first, reply);
      await tester.pump(const Duration(milliseconds: 400));
      typed = await tapHit(tester, byKey('chat-send'), '"chat-send"');
      await pumpUntil(
        tester,
        () => calls(
          '/api/v1/trips/$id/messages',
          method: 'POST',
          from: mark,
        ).any((c) => c.status != null || c.error != null),
        timeout: const Duration(seconds: 20),
      );
    }
    final posted = calls(
      '/api/v1/trips/$id/messages',
      method: 'POST',
      from: mark,
    ).map((c) => c.status ?? c.error).toList();
    final read = await peer.api.messages(id);
    final items = read.map?['items'];
    final driverSees =
        items is List &&
        items.any(
          (m) => m is Map && m['from'] == 'rider' && m['text'] == reply,
        );
    final second = 'TL driver again ${TripRun.randomTag()}';
    final sent2 = await peer.api.sendMessage(id, second);
    final seen2 =
        opened &&
        await pumpUntil(
          tester,
          () => shows(find.text(second)),
          timeout: TripRun.stageWait,
        );
    await watch.run('chat-close', () => backToTrip(tester));
    await wait(tester, const Duration(seconds: 1));
    final unreadAfter = chatUnread();
    final detail =
        'driver send ${sent1.short}; rider badge=$badge after ${badgeLag ?? '-'} s; '
        'chat opened=$opened driver text shown=$seen1; reply typed=$typed '
        'POST=$posted driver reads it=$driverSees (${read.short}); driver '
        'again ${sent2.short} shown while open=$seen2; unread after close='
        '$unreadAfter; back on trip=${onTripTop()}';
    sent1.ok &&
            badge &&
            (badgeLag ?? 99) <= TripRun.uiLagLimit.inSeconds &&
            opened &&
            seen1 &&
            driverSees &&
            seen2 &&
            unreadAfter == 0 &&
            onTripTop()
        ? log.pass('CHAT', title, detail)
        : log.fail('CHAT', title, detail);
  }

  /// The rider calls from the trip sheet; the driver (HTTP) answers and
  /// hangs up. States only: Test Lab has no audio peer, so "Call failed"
  /// after the answer counts as the state flow working (reported).
  Future<void> _callOut() async {
    const title = 'rider call: ringing, answered, ended, back to the trip';
    if (late) return log.skip('CALL-OUT', title, 'not run: time limit near');
    final id = tripId!;
    final mark = rec.length;
    String? callId;
    ApiAnswer? answered, ended;
    final lines = <String>{};
    await watch.run('call-out', () async {
      await tapOnSheet(tester, 'waiting-call');
      await pumpUntil(tester, callOpen, timeout: const Duration(seconds: 10));
      await pumpUntil(
        tester,
        () => calls(
          '/api/v1/trips/$id/call',
          method: 'POST',
          from: mark,
        ).any((c) => c.status != null || c.error != null),
        timeout: const Duration(seconds: 20),
      );
      final post = calls('/api/v1/trips/$id/call', method: 'POST', from: mark);
      final ans = post.isEmpty ? null : post.last.answer;
      callId = ans is Map ? ans['callId'] as String? : null;
      if (callStateLine() case final l?) lines.add(l);
      if (callId != null) {
        answered = await peer.api.answerCall(callId!);
        await wait(tester, const Duration(seconds: 4));
        if (callStateLine() case final l?) lines.add(l);
        ended = await peer.api.endCall(callId!, 'hangup');
        await pumpUntil(tester, () {
          if (callStateLine() case final l?) lines.add(l);
          return !callOpen();
        }, timeout: const Duration(seconds: 20));
      }
      if (callOpen()) await tapKey(tester, 'call-close');
      await pumpUntil(
        tester,
        () => !callOpen(),
        timeout: const Duration(seconds: 8),
      );
      await backToTrip(tester);
    });
    final post = calls(
      '/api/v1/trips/$id/call',
      method: 'POST',
      from: mark,
    ).map((c) => c.status ?? c.error).toList();
    final endedShown = lines.contains(L10n.current.callEnded);
    final failedShown = lines.contains(L10n.current.callFailed);
    final detail =
        'rider call POST=$post callId=${callId != null}; driver answer '
        '${answered?.short} state=${answered?.map?['state']}; driver end '
        '${ended?.short} state=${ended?.map?['state']}; rider screen lines='
        '${lines.toList()}${failedShown ? ' (Call failed: no audio peer on '
                  'Test Lab, state flow only)' : ''}; back on trip=${onTripTop()}';
    post.any((s) => s == 200 || s == 201) &&
            answered?.map?['state'] == 'answered' &&
            ended?.map?['state'] == 'ended' &&
            (endedShown || failedShown) &&
            onTripTop()
        ? log.pass('CALL-OUT', title, detail)
        : log.fail('CALL-OUT', title, detail);
  }

  /// The driver (HTTP) calls; the rider's call screen rings, the rider
  /// answers, the driver hangs up, the screen goes.
  Future<void> _callIn() async {
    const title = 'driver call: rings on the phone, answered, ended';
    if (late) return log.skip('CALL-IN', title, 'not run: time limit near');
    final id = tripId!;
    final mark = rec.length;
    final lines = <String>{};
    ApiAnswer? ended;
    final call = await peer.api.call(id);
    final callId = call.map?['callId'] as String?;
    final t0 = DateTime.now();
    var rang = false;
    var tapped = false;
    await watch.run('call-in', () async {
      rang = await pumpUntil(
        tester,
        () => tester.any(byKey('call-answer').hitTestable()),
        timeout: TripRun.stageWait,
      );
      if (callStateLine() case final l?) lines.add(l);
      if (rang) tapped = await tapKey(tester, 'call-answer');
      await wait(tester, const Duration(seconds: 3));
      if (callStateLine() case final l?) lines.add(l);
      if (callId != null) ended = await peer.api.endCall(callId, 'hangup');
      await pumpUntil(tester, () {
        if (callStateLine() case final l?) lines.add(l);
        return !callOpen();
      }, timeout: const Duration(seconds: 15));
      if (callOpen()) await tapKey(tester, 'call-close');
      await backToTrip(tester);
    });
    final lag = rang ? DateTime.now().difference(t0).inSeconds : null;
    final answers = callsMatching(
      RegExp(r'^/api/v1/calls/[^/]+/answer$'),
      method: 'POST',
      from: mark,
    ).map((c) => c.status ?? c.error).toList();
    final detail =
        'driver call ${call.short} callId=${callId != null}; rider rang=$rang '
        'answer tapped=$tapped answer POST=$answers; driver end ${ended?.short}; '
        'rider lines=${lines.toList()}; back on trip=${onTripTop()} '
        '(ring shown within ${lag ?? '-'} s incl. the answer)';
    call.ok &&
            rang &&
            tapped &&
            answers.any((s) => s is int && s < 300) &&
            onTripTop()
        ? log.pass('CALL-IN', title, detail)
        : log.fail('CALL-IN', title, detail);
  }

  /// SOS on the trip's safety kit (never pressed): the button shows the
  /// zone's main number, and the numbers the app holds are the server's
  /// for the trip's zone (G17).
  Future<void> _sos() async {
    const title = 'SOS shows; the app holds the zone numbers (G17)';
    if (late) return log.skip('SOS', title, 'not run: time limit near');
    final (status, served) = await _zoneNumbers();
    var opened = false;
    await watch.run('safety-open', () async {
      opened = await openSafetyKit(tester);
    });
    final sos = byKey('safety-sos');
    final sosShown = shows(sos);
    final label = textsUnder(sos).join(' ');
    final held = [for (final n in EmergencyNumbers.current) n.number];
    if (opened) await log.screenshot(tester, 'trip-safety');
    await watch.run('safety-close', () async {
      if (safetyKitOpen()) await systemBack(tester);
      await pumpUntil(
        tester,
        () => !safetyKitOpen(),
        timeout: const Duration(seconds: 5),
      );
      await backToTrip(tester);
    });
    final mainShown = served.isNotEmpty && label.contains(served.first);
    final detail =
        'kit opened=$opened SOS button=$sosShown (not pressed) main number '
        'on it=$mainShown; zone config $status server=$served app holds=$held '
        'received=${EmergencyNumbers.received}; back on trip=${onTripTop()}';
    sosShown &&
            served.isNotEmpty &&
            held.join(',') == served.join(',') &&
            onTripTop()
        ? log.pass('SOS', title, detail)
        : log.fail('SOS', title, detail);
  }

  /// The server's long-stop ride check (rideCheck.stopMinutes still
  /// within 50 m on board): the driver's fixes stay at the pickup, the
  /// rider's card must show, the rider's OK must reach the server; the
  /// driver answers OK over HTTP.
  Future<void> _rideCheck() async {
    const title = 'ride check card on the phone, answered OK';
    final config = rec.lastAnswer['/api/v1/rider/config'];
    final rc = config is Map ? config['rideCheck'] : null;
    final on = rc is Map ? rc['on'] != false : true;
    final stopMin = rc is Map && rc['stopMinutes'] is num
        ? (rc['stopMinutes'] as num).toDouble()
        : 2.0;
    if (!on) {
      return log.skip(
        'RIDE-CHECK',
        title,
        'NOT CHECKED: rideCheck.on is false for this zone on staging',
      );
    }
    final since = onBoardAt ?? DateTime.now();
    final until = since.add(Duration(seconds: (stopMin * 60).round() + 90));
    if (until.isAfter(softDeadline)) {
      return log.skip(
        'RIDE-CHECK',
        title,
        'NOT CHECKED: waiting $stopMin min still would pass the time limit',
      );
    }
    final mark = rec.length;
    await watch.run('ride-check', () async {
      while (rideCheckSeenAt == null &&
          DateTime.now().isBefore(until) &&
          !stopped) {
        await rideCheckGate();
        await wait(tester, const Duration(seconds: 2));
      }
      await wait(tester, const Duration(seconds: 3));
    });
    final driverView = await peer.trip(tripId!);
    final check = driverView?['rideCheck'];
    String? driverAnswer;
    if (check is Map && check['checkId'] is String) {
      final a = await peer.api.answerRideCheck(
        tripId!,
        check['checkId'] as String,
        check['trigger'],
      );
      driverAnswer = a.short;
    }
    final view = await riderView();
    final after = view?['rideCheck'];
    final answers = after is Map ? after['answers'] : null;
    final posts = calls(
      '/api/v1/rider/trips/$tripId/ride-check',
      method: 'POST',
      from: mark,
    ).map((c) => c.status ?? c.error).toList();
    final riderOk = answers is Map && answers['rider'] != null;
    final detail =
        'card seen=${rideCheckSeenAt != null} after '
        '${rideCheckSeenAt?.difference(since).inSeconds ?? '-'} s on board '
        '(stopMinutes=$stopMin); rider POST=$posts; server trigger='
        '${after is Map ? after['trigger'] : null} rider answer='
        '${answers is Map ? answers['rider'] : null}; driver answered $driverAnswer';
    rideCheckSeenAt != null && riderOk
        ? log.pass('RIDE-CHECK', title, detail)
        : log.fail('RIDE-CHECK', title, detail);
  }
}
