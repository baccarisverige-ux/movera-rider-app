import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/config/emergency_numbers.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/features/destination_search/presentation/route_picker_page.dart';
import 'package:movera_rider/features/history/presentation/ride_history.dart';
import 'package:movera_rider/features/home/presentation/side_menu.dart';
import 'package:movera_rider/features/payments/presentation/pay_with_page.dart';
import 'package:movera_rider/features/pickup/presentation/set_pickup_page.dart';
import 'package:movera_rider/features/reservations/presentation/ride_scheduled.dart';
import 'package:movera_rider/features/reservations/presentation/upcoming_reservation.dart';
import 'package:movera_rider/features/ride_selection/presentation/select_ride.dart';
import 'package:movera_rider/features/scheduled_rides/presentation/select_date_time.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:movera_rider/shared/formatters/money.dart';

import 'check_log.dart';
import 'cleanup_scope.dart';
import 'driver_peer.dart';
import 'movera_api.dart';
import 'rider_session.dart';
import 'rider_steps.dart';
import 'transition_watch.dart';
import 'trip_steps.dart';

part 'trip_book.dart';
part 'trip_cleanup.dart';
part 'trip_extras.dart';
part 'trip_money.dart';
part 'trip_scheduled.dart';

/// G31 rider (owner 2026-11-12: "then the RIDER app on phone (driver via
/// API) with the same checks"): one whole trip on a real Test Lab phone.
/// The RIDER is the real app on the phone; the DRIVER is played over HTTP
/// by this test ([DriverPeer], the shared big-test driver handed over at
/// run time).
///
/// Every step is one `MOVERA-TL CHECK` line with a time limit and a clear
/// FAIL detail (a miss names the key); the run always reaches the clean-up
/// (open trips closed, the driver offline). Lessons of the driver suite's
/// device runs 4-7 kept: no pump while the app is hidden/paused, a
/// watchdog that cleans up over HTTP, the END line, a timeout is a JUnit
/// failure, only hit-testable widgets are tapped, sheets are opened before
/// their controls are tapped.
class TripRun extends RiderSession {
  TripRun(super.tester, super.log, {this.scheduled = false}) {
    peer = DriverPeer(base);
    watch = TransitionWatch(tester, log, this);
  }

  late final DriverPeer peer;
  late final TransitionWatch watch;

  /// The `trip-scheduled` scenario: booked-for-later rides (and the
  /// cancel case) instead of a live one.
  final bool scheduled;

  /// Trip ids this run booked: their recorded `POST /trips` answers (the
  /// clean-up closes these, see [cleanupScope]).
  final List<String> booked = <String>[];

  /// The rider's open trips (active + booked) read before the run's first
  /// booking; null = not readable. Never closed by the clean-up.
  Set<String>? openBeforeBook;

  /// A `POST /trips` of this run got no usable answer: the trip may exist.
  bool bookAnswerLost = false;

  /// The driver starts ~350 m south-west of the rider's pickup (the
  /// phone's mock position); the drop-off is where the rider typed.
  late final (double, double) driverStart = DriverPeer.offset(
    lat,
    lng,
    north: -250,
    east: -250,
  );

  final DateTime startedAt = DateTime.now();

  /// Optional checks are skipped past this point.
  late final DateTime softDeadline = startedAt.add(softAfter);

  /// The order of the stops (driver suite run 6), from [startedAt]: hard
  /// stop 15 min ([hardAfter]) -> watchdog 15 min 45 s ([watchAfter], only
  /// when a pump never returned) -> clean-up done by ~17 min 30 s
  /// ([cleanupBudget]) -> the test's own timeout 18 min ([testLimit]) ->
  /// Test Lab's --timeout 25 min (android-test-apk.yml, install and start
  /// count too).
  late final DateTime hardDeadline = startedAt.add(hardAfter);

  static const Duration softAfter = Duration(minutes: 13);
  static const Duration hardAfter = Duration(minutes: 15);
  static const Duration watchAfter = Duration(minutes: 15, seconds: 45);
  static const Duration cleanupBudget = Duration(minutes: 2, seconds: 30);
  static const Duration testLimit = Duration(minutes: 18);

  /// The longest the rider screen may take to show a trip step after the
  /// driver's 2xx (UI-LAG; owner Q6 proposed 15 s, not answered yet). The
  /// test waits [stageWait] for it.
  static const Duration uiLagLimit = Duration(seconds: 15);
  static const Duration stageWait = Duration(seconds: 20);

  bool stepsDone = false;
  bool cleanedUp = false;
  bool _written = false;
  String currentStep = 'start';

  bool get late => DateTime.now().isAfter(softDeadline);

  bool get stopped => DateTime.now().isAfter(hardDeadline);

  String? tripId;
  Map<String, dynamic>? lastRiderView;
  Map<String, dynamic>? preview;
  bool accepted = false;
  bool started = false;
  bool completed = false;
  DateTime? onBoardAt;
  DateTime? rideCheckSeenAt;

  /// The drop-off the server booked (lat, lng), for the drive there.
  (double, double)? dropoff;

  /// The pickup the server booked (the phone's position, reverse-geocoded).
  (double, double)? pickup;

  /// Runs one step: an exception is that step's FAIL, never the end.
  Future<void> step(
    String id,
    String title,
    Future<void> Function() body,
  ) async {
    if (stopped) {
      return log.skip(id, title, 'not run: hard time limit (clean-up next)');
    }
    log.step(id);
    currentStep = id;
    CheckLog.missed = null;
    try {
      await body();
    } catch (error, stack) {
      log.fail(id, title, 'stopped by ${error.runtimeType}: $error');
      CheckLog.say('STACK ${stack.toString().split('\n').take(5).join(' | ')}');
    }
  }

  /// The trip as the rider's server view (`GET /trips/{id}` with the
  /// app's session).
  Future<Map<String, dynamic>?> riderView([String? id]) async {
    final trip = id ?? tripId;
    if (trip == null) return null;
    refreshRiderToken();
    final answer = await riderApi.trip(trip);
    if (answer.ok && (id == null || id == tripId)) lastRiderView = answer.map;
    return answer.ok ? answer.map : null;
  }

  String? get serverStatus => lastRiderView?['status'] as String?;

  /// Polls the server every 2 s (pumping meanwhile) until a status in
  /// [want] (or a terminal one) or [timeout].
  Future<String?> waitStatus(Set<String> want, Duration timeout) async {
    final end = DateTime.now().add(timeout);
    while (true) {
      final status = (await riderView())?['status'] as String?;
      if (status != null &&
          (want.contains(status) || terminalStatuses.contains(status))) {
        return status;
      }
      if (DateTime.now().isAfter(end) || stopped) return status;
      await wait(tester, const Duration(seconds: 2));
    }
  }

  /// UI-LAG of one stage: [took] seconds after the driver's 2xx. Returns
  /// the text for the check line; [ok] false above [uiLagLimit] or never.
  (bool, String) lag(int? took) => took == null
      ? (false, 'UI-LAG: not shown in ${stageWait.inSeconds} s')
      : (
          took <= uiLagLimit.inSeconds,
          'UI-LAG ${took}s (FAIL above ${uiLagLimit.inSeconds}s)',
        );

  /// The rider's ride check card, answered "OK" the way a rider would,
  /// whichever step is running.
  Future<void> rideCheckGate() async {
    if (!shows(byKey('ride-check-card'))) return;
    rideCheckSeenAt ??= DateTime.now();
    CheckLog.say('STEP ride check card shown: answered OK');
    final ok = byKey('ride-check-ok').hitTestable();
    if (tester.any(ok)) {
      await tester.tap(ok.first, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 600));
    }
    final done = byKey('ride-check-done').hitTestable();
    if (tester.any(done)) {
      await tester.tap(done.first, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 400));
    }
  }

  Future<void> all({
    required String phone,
    required String code,
    required String peerPhone,
  }) async {
    stepsHardStop = hardDeadline;
    final watchdog = Timer(
      startedAt.add(watchAfter).difference(DateTime.now()),
      () => unawaited(_hung()),
    );
    try {
      await _start();
      if (!await _signIn(phone, code)) return;
      await step('DRIVER-SIGN-IN', 'driver signs in over HTTP', () async {
        final error = await peer.signIn(phone: peerPhone, code: code);
        error == null
            ? log.pass(
                'DRIVER-SIGN-IN',
                'driver signs in over HTTP',
                'signed in',
              )
            : log.fail('DRIVER-SIGN-IN', 'driver signs in over HTTP', error);
      });
      if (!peer.api.signedIn) return;
      await step('DRIVER-ONLINE', 'driver online near the pickup', () async {
        final error = await peer.goOnline(driverStart.$1, driverStart.$2);
        final detail =
            'server=${peer.onlineStatus} categories=${peer.categoryIds.length} '
            'start ~350 m from the rider; fixes every '
            '${DriverPeer.feedEvery.inSeconds} s';
        error == null
            ? log.pass('DRIVER-ONLINE', 'driver online near the pickup', detail)
            : log.fail(
                'DRIVER-ONLINE',
                'driver online near the pickup',
                '$error; $detail',
              );
      });
      if (!peer.online) return;
      await step('SOS-ZONES', 'every zone sends emergency numbers', _sosZones);
      if (scheduled) {
        await _scheduledScenario();
      } else {
        await _liveScenario();
      }
    } catch (error, stack) {
      log.fail('RUN', 'checks ran to the end', 'stopped by $error');
      CheckLog.say('STACK ${stack.toString().split('\n').take(6).join(' | ')}');
    } finally {
      stepsDone = true;
      watchdog.cancel();
      stepsHardStop = null;
      if (stopped) {
        CheckLog.say(
          'STEP hard time limit (${TripRun.hardAfter.inMinutes} min) reached: '
          'clean-up and driver offline now',
        );
      }
      final testEnd = startedAt
          .add(TripRun.testLimit)
          .subtract(const Duration(seconds: 20));
      var cleanupEnd = DateTime.now().add(TripRun.cleanupBudget);
      final latest = testEnd.subtract(const Duration(seconds: 40));
      if (latest.isBefore(cleanupEnd)) cleanupEnd = latest;
      if (!cleanedUp) {
        cleanedUp = true;
        await _cleanup(until: cleanupEnd);
        await _driverOffline();
      }
    }
  }

  /// Starts the app with the recording client (START check).
  Future<void> _start() async {
    currentStep = 'START';
    await start();
    final used = await pumpUntil(
      tester,
      () => clientInUse,
      timeout: const Duration(seconds: 30),
      dismiss: false,
    );
    used
        ? log.pass(
            'START',
            'app starts with the recording client',
            'first app call recorded (${rec.calls.first.label})',
          )
        : log.fail(
            'START',
            'app starts with the recording client',
            'recording client not in use: no app call in 30 s; RELOAD and '
                'ERRORS checks NOT CHECKED',
          );
  }

  Future<bool> _signIn(String phone, String code) async {
    log.step('sign in (server ${base.host})');
    currentStep = 'SIGN-IN';
    const title = 'test rider reaches Home';
    final error = await guard(() => signIn(tester, phone: phone, code: code));
    if (error != null) {
      log.fail('SIGN-IN', title, error);
      log.skip('TRIP', 'trip lifecycle', 'not run: sign-in failed');
      return false;
    }
    final session = await adoptAppSession();
    // F1 (supervisor 2026-11-13): a trip the rider had before the run is
    // never touched. The snapshot is taken before the first booking; an
    // active one (restored on start) stops the run with a clear line.
    openBeforeBook = await riderApi.openTripIds();
    final active = await riderApi.activeTrip();
    if (active.status == 200 && active.map?['tripId'] is String) {
      log.fail(
        'SIGN-IN',
        title,
        'the test rider has an open trip from before the run '
            '(${active.map!['status']}); not touched: close it by hand, then '
            'run again',
      );
      return false;
    }
    await backToHome(tester);
    final home = await pumpUntil(
      tester,
      onHomeOnly,
      timeout: const Duration(seconds: 30),
    );
    final detail =
        'Home alone=$home app session=${session ? 'yes' : 'no'} '
        'active trip before=${active.short} open before the run='
        '${openBeforeBook?.length ?? 'unknown'}';
    if (!home || !session) {
      log.fail('SIGN-IN', title, detail);
      return false;
    }
    log.pass('SIGN-IN', title, detail);
    await wait(tester, const Duration(seconds: 3));
    watch.baseline();
    await log.screenshot(tester, 'home');
    return true;
  }

  Future<void> _liveScenario() async {
    await step(
      'BOOK',
      'rider books a cash trip in the app',
      () => _book('BOOK'),
    );
    if (tripId == null) return;
    await step('SEARCHING', 'Finding, offer to the test driver', _searching);
    if (!accepted) return;
    await _tripSteps(extras: true);
  }

  /// From "driver on the way" to History, the same for a live and a
  /// booked ride. [extras]: chat, calls, SOS, ride check.
  Future<void> _tripSteps({required bool extras}) async {
    await step('ARRIVING', 'driver on the way, map kept', _arriving);
    await step(
      'SWITCH-1',
      'background/resume keeps the trip',
      () => _switch('1'),
    );
    await step('ARRIVED', 'arrived: the rider sees the PIN', _arrived);
    await step('PIN', 'PIN on screen = server, trip starts', _pin);
    if (!started) return;
    await step('PAY-IN-CAR', 'in-trip line: cash and the fare', _payInCarLine);
    if (extras) {
      // Stationary at the pickup with the rider on board: the server's
      // long-stop ride check clock runs while these go on.
      await step('CHAT', 'chat both ways, unread badge', _chat);
      await step('CALL-OUT', 'rider calls: ring, answer, end', _callOut);
      await step('CALL-IN', 'driver calls: answer, end', _callIn);
      await step(
        'SWITCH-2',
        'background/resume keeps the trip',
        () => _switch('2'),
      );
      await step('SOS', 'SOS on the trip, zone numbers', _sos);
      await step('RIDE-CHECK', 'ride check card, answered OK', _rideCheck);
    }
    await step('DROPOFF', 'driver drives to the drop-off', _dropoff);
    await step('PAY', 'completed: amount, pay the driver in the car', _pay);
    if (!completed) return;
    await step('RATE', 'stars + Done send the rating, Home shows', _rate);
    await step('RECEIPT', 'receipt = what was paid', _receipt);
    await step('HISTORY', 'history lists the trip, its receipt', _history);
  }

  Future<void> _hung() async {
    if (stepsDone || cleanedUp) return;
    cleanedUp = true;
    log.fail(
      'RUN',
      'hung',
      'no pump returned in $currentStep (watchdog at '
          '${watchAfter.inMinutes} min ${watchAfter.inSeconds % 60} s)',
    );
    try {
      final until = DateTime.now().add(const Duration(minutes: 1));
      await _closeTrips(until: until).timeout(
        const Duration(seconds: 75),
        onTimeout: () => log.fail(
          'CLEANUP',
          'no open test trip is left',
          'watchdog: trips not closed in 75 s',
        ),
      );
      await _driverOffline().timeout(
        const Duration(seconds: 45),
        onTimeout: () => log.fail(
          'OFFLINE',
          'the test driver is offline',
          'watchdog: offline took over 45 s',
        ),
      );
    } catch (error) {
      log.fail('RUN', 'watchdog clean-up', 'stopped by ${error.runtimeType}');
    } finally {
      await writeResults();
    }
  }

  /// summary.json / SUMMARY / SUMMARY-JSON / transitions, then the END
  /// line; once only (the test's `finally` and the watchdog both call it).
  Future<void> writeResults() async {
    if (_written) return;
    _written = true;
    await log.write(
      requestLog: [for (final c in rec.calls) '$c'],
      extra: {'transitions': watch.rows},
    );
    log.end();
  }

  static String randomTag() => math.Random().nextInt(1 << 20).toRadixString(36);

  /// Money on the wire as the rider app writes it ("123 kr").
  static String? shown((int, String)? money) =>
      money == null ? null : formatMoney(Money(money.$1, money.$2));

  /// True when one of [texts] holds [money] as the app writes it (to the
  /// öre, or rounded to the krona as the booked-fare line does).
  static bool hasMoney(Iterable<String> texts, (int, String)? money) {
    if (money == null) return false;
    final m = Money(money.$1, money.$2);
    final forms = {formatMoney(m), formatMoney(m, whole: true)};
    return texts.any((t) => forms.any(t.contains));
  }
}
