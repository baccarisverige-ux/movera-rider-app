part of 'trip_run.dart';

/// Sensitive buttons 2026-11-20 (owner: "make Firebase test for sensitive
/// buttons", Rules audits/impact/device-proof-2026-11-20.md): the rider
/// buttons the trip-lifecycle run only looked at, now pressed.
///
/// - SOS-PRESS: the kit's SOS button is tapped during the trip. The phone
///   dialer is NEVER opened: [TelLauncher] (installed for the whole run)
///   keeps every `tel:` launch the app asks for and answers "opened"
///   without starting an intent. PASS: the app asked for `tel:` + the
///   zone's main number AND `POST /rider/trips/{id}/sos` answered 2xx.
/// - SHARE: the kit's Share trip button. PASS: the share call answered
///   2xx, or (no trusted contact on the test rider) the share page opened.
/// - FREE-CANCEL: after the full trip a second cash ride is booked in the
///   app, the test driver accepts over HTTP, and the rider cancels in the
///   app at once (inside the free window). PASS: server
///   `cancelled_by_rider` with no fee (or fee 0).
extension _TripSensitive on TripRun {
  Future<void> _sosPress() async {
    const id = 'SOS-PRESS';
    const title = 'SOS asks for the tel: dial and alerts Movera';
    if (late) return log.skip(id, title, 'not run: time limit near');
    final trip = tripId!;
    final (_, served) = await _zoneNumbers();
    final mark = rec.length;
    final dialsBefore = TelLauncher.asked.length;
    final opened = await openSafetyKit(tester);
    final sos = byKey('safety-sos');
    final tapped = opened && await tapHit(tester, sos, '"safety-sos"');
    await pumpUntil(
      tester,
      () => callsMatching(
        RegExp(r'/sos$'),
        method: 'POST',
        from: mark,
      ).any((c) => c.status != null || c.error != null),
      timeout: const Duration(seconds: 20),
    );
    final posts = callsMatching(
      RegExp(r'/sos$'),
      method: 'POST',
      from: mark,
    ).toList();
    final postOk = posts.any(
      (c) =>
          c.path.contains(Uri.encodeComponent(trip)) &&
          (c.status ?? 0) >= 200 &&
          (c.status ?? 0) < 300,
    );
    final dials = TelLauncher.asked.skip(dialsBefore).toList();
    final want = served.isEmpty ? null : 'tel:${served.first}';
    final dialOk = want != null && dials.contains(want);
    if (opened) await log.screenshot(tester, 'trip-sos-pressed');
    if (safetyKitOpen()) await systemBack(tester);
    await pumpUntil(
      tester,
      () => !safetyKitOpen(),
      timeout: const Duration(seconds: 5),
    );
    await backToTrip(tester);
    final detail =
        'kit opened=$opened SOS tapped=$tapped dial asked=$dials (want '
        '${want ?? 'a zone number'}; no real dial) SOS POST='
        '${posts.map((c) => c.status ?? c.error).toList()} '
        'back on trip=${onTripTop()}';
    dialOk && postOk && onTripTop()
        ? log.pass(id, title, detail)
        : log.fail(id, title, detail);
  }

  Future<void> _share() async {
    const id = 'SHARE';
    const title = 'Share trip starts sharing or opens the share page';
    if (late) return log.skip(id, title, 'not run: time limit near');
    final mark = rec.length;
    final opened = await openSafetyKit(tester);
    final button = find.descendant(
      of: find.byType(RideSafetyKitSheet),
      matching: find.text(L10n.current.shareTrip),
    );
    final tapped = opened && await tapHit(tester, button, '"Share trip"');
    var page = false;
    await pumpUntil(
      tester,
      () =>
          (page = shows(find.byType(TripSharePage))) ||
          callsMatching(
            RegExp(r'/share$'),
            method: 'POST',
            from: mark,
          ).any((c) => c.status != null || c.error != null),
      timeout: const Duration(seconds: 15),
    );
    final posts = callsMatching(
      RegExp(r'/share$'),
      method: 'POST',
      from: mark,
    ).map((c) => c.status ?? c.error).toList();
    final postOk = posts.any((s) => s is int && s >= 200 && s < 300);
    await log.screenshot(tester, 'trip-share');
    for (var i = 0; i < 3 && !onTripTop(); i++) {
      await systemBack(tester);
    }
    await backToTrip(tester);
    final detail =
        'kit opened=$opened Share tapped=$tapped share POST=$posts '
        'share page (no contact yet)=$page back on trip=${onTripTop()}';
    tapped && (postOk || (page && posts.isEmpty)) && onTripTop()
        ? log.pass(id, title, detail)
        : log.fail(id, title, detail);
  }

  Future<void> _freeCancel() async {
    const id = 'FREE-CANCEL';
    const title = 'rider cancels at once after the match: no fee';
    if (late) return log.skip(id, title, 'not run: time limit near');
    await backToHome(tester);
    await _book('CANCEL-BOOK');
    final trip = tripId;
    if (trip == null) {
      return log.skip(id, title, 'not run: second booking failed');
    }
    final (offer, _) = await peer.waitOffer(
      trip,
      const Duration(seconds: 90),
      stop: () => stopped,
    );
    if (offer == null) {
      return log.fail(id, title, 'no offer to the test driver in 90 s');
    }
    final version = offer['version'];
    final accept = await peer.api.acceptOffer(
      offer['offerId'] as String,
      version is num ? version.toInt() : 1,
    );
    if (!accept.ok) {
      return log.fail(id, title, 'driver accept ${accept.short}');
    }
    peer.tripId = trip;
    final acceptedAt = DateTime.now();
    await waitStage(
      tester,
      stageFor['accepted']!,
      timeout: TripRun.stageWait,
      extra: () => tripScreenShown() && shows(byKey('waiting-panel')),
    );
    final mark = rec.length;
    final cancelButton = shows(byKey('active-trip-cancel'))
        ? byKey('active-trip-cancel')
        : find.bySemanticsLabel(L10n.current.cancelRide);
    final tapped = await tapHit(tester, cancelButton, '"Cancel ride"');
    final sheet = find.byType(CancelRideSheet);
    await pumpUntil(
      tester,
      () => shows(sheet),
      timeout: const Duration(seconds: 8),
    );
    final feeNote = shows(byKey('cancel-fee-note'))
        ? textsUnder(byKey('cancel-fee-note')).join(' ')
        : 'none';
    var confirmed = false;
    final yes = find.descendant(of: sheet, matching: find.byType(TextButton));
    if (shows(yes)) {
      confirmed = await tapHit(tester, yes.first, 'cancel sheet confirm');
    }
    final reasons = byKeyPrefix('cancel-reason-');
    await pumpUntil(
      tester,
      () => keysOf(reasons).any((k) => k != 'cancel-reason-submit'),
      timeout: const Duration(seconds: 8),
    );
    final first = keysOf(reasons).where((k) => k != 'cancel-reason-submit');
    var submitted = false;
    if (first.isNotEmpty) {
      await tapKey(tester, first.first);
      submitted = await tapKey(tester, 'cancel-reason-submit');
    }
    await pumpUntil(
      tester,
      () => callsMatching(
        RegExp(r'/cancel$'),
        method: 'POST',
        from: mark,
      ).any((c) => c.status != null || c.error != null),
      timeout: const Duration(seconds: 20),
    );
    final seconds = DateTime.now().difference(acceptedAt).inSeconds;
    final view = await riderView();
    final c = view?['cancellation'];
    final fee = c is Map ? moneyOf(c['fee']) : null;
    final free = fee == null || fee.$1 == 0;
    await wait(tester, const Duration(seconds: 2));
    await backToHome(tester);
    final detail =
        'Cancel tapped=$tapped fee note="$feeNote" confirm=$confirmed '
        'reason submitted=$submitted ${seconds}s after the match; server='
        '${view?['status']} fee=${TripRun.shown(fee) ?? 'none'}';
    view?['status'] == 'cancelled_by_rider' && free
        ? log.pass(id, title, detail)
        : log.fail(id, title, '$detail (want cancelled_by_rider, no fee)');
    tripId = null;
  }
}

/// Keeps every `tel:` URL the app asks to open and answers "opened"
/// without any intent (no dial screen, never a call). Any other URL goes
/// to the real platform.
class TelLauncher extends UrlLauncherPlatform {
  TelLauncher(this._real);

  final UrlLauncherPlatform _real;

  static final List<String> asked = <String>[];

  static void install() {
    final now = UrlLauncherPlatform.instance;
    if (now is! TelLauncher) UrlLauncherPlatform.instance = TelLauncher(now);
  }

  @override
  LinkDelegate? get linkDelegate => _real.linkDelegate;

  @override
  Future<bool> canLaunch(String url) async =>
      url.startsWith('tel:') || await _real.canLaunch(url);

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    if (url.startsWith('tel:')) {
      asked.add(url);
      CheckLog.say('STEP tel: launch kept by the test (no dial)');
      return true;
    }
    return _real.launchUrl(url, options);
  }

  @override
  Future<bool> launch(
    String url, {
    required bool useSafariVC,
    required bool useWebView,
    required bool enableJavaScript,
    required bool enableDomStorage,
    required bool universalLinksOnly,
    required Map<String, String> headers,
    String? webOnlyWindowName,
  }) async {
    if (url.startsWith('tel:')) {
      asked.add(url);
      return true;
    }
    return _real.launch(
      url,
      useSafariVC: useSafariVC,
      useWebView: useWebView,
      enableJavaScript: enableJavaScript,
      enableDomStorage: enableDomStorage,
      universalLinksOnly: universalLinksOnly,
      headers: headers,
      webOnlyWindowName: webOnlyWindowName,
    );
  }

  @override
  Future<bool> supportsMode(PreferredLaunchMode mode) =>
      _real.supportsMode(mode);

  @override
  Future<bool> supportsCloseForMode(PreferredLaunchMode mode) =>
      _real.supportsCloseForMode(mode);

  @override
  Future<void> closeWebView() => _real.closeWebView();
}
