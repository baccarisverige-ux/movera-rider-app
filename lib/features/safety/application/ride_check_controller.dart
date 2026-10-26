import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:movera_rider/core/debug/web_qa_hooks.dart';
import 'package:movera_rider/core/logging/app_log.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/core/utils/request_id.dart';
import 'package:movera_rider/features/safety/application/emergency_call_service.dart';
import 'package:movera_rider/features/safety/application/ride_check_service.dart';
import 'package:movera_rider/features/safety/application/safety_audio_service.dart';
import 'package:movera_rider/features/safety/application/safety_controller.dart';
import 'package:movera_rider/features/safety/domain/ride_check.dart';
import 'package:movera_rider/features/safety/domain/ride_check_monitor.dart';
import 'package:movera_rider/features/safety/domain/ride_check_questions.dart';
import 'package:movera_rider/features/safety/domain/ride_check_record.dart';
import 'package:movera_rider/features/safety/domain/ride_check_trigger.dart';
import 'package:movera_rider/l10n/l10n.dart';

enum RideCheckStep { main, followUp }

enum RideCheckAlertState { none, sending, sent, failed }

enum RideCheckOpenResult {
  shown,
  busy,
  alreadyShown,
  riderOff,
  triggerOff,
  noTrip,
  notMonitoring,
  noTrigger,
}

/// The Ride check card on screen. The controller is its only writer.
@immutable
class RideCheckSession {
  const RideCheckSession({
    required this.checkId,
    required this.rideId,
    required this.trigger,
    required this.shownAt,
    this.reason = const RideCheckReason(),
    this.step = RideCheckStep.main,
    this.row,
    this.answers = const [],
    this.choices = const {},
    this.note = '',
    this.alertState = RideCheckAlertState.none,
    this.alertId,
    this.called112 = false,
    this.callError,
    this.recordingNote,
  });

  final String checkId;
  final String rideId;
  final RideCheckTrigger trigger;
  final RideCheckReason reason;
  final DateTime shownAt;
  final RideCheckStep step;

  /// The row the rider tapped (follow-up step).
  final RideCheckRow? row;
  final List<RideCheckAnswer> answers;

  /// The follow-up's chosen option per question id.
  final Map<String, RideCheckOptionId> choices;
  final String note;
  final RideCheckAlertState alertState;
  final String? alertId;
  final bool called112;

  /// The phone dialer could not be opened.
  final String? callError;
  final String? recordingNote;

  List<RideCheckRow> get rows => rideCheckRowsFor(trigger);

  /// Answered questions in the follow-up, for its step bar.
  int get answeredQuestions {
    final questions = row?.followUp.questions ?? const [];
    return questions.where((q) => choices.containsKey(q.id)).length;
  }

  /// The follow-up shows the big "Call 112 now".
  bool get showsCallNow {
    final followUp = row?.followUp;
    if (followUp == null) return false;
    return followUp.questions.any((question) {
      final choice = choices[question.id];
      return choice != null && question.callWhen.contains(choice);
    });
  }

  bool get alerted =>
      alertState == RideCheckAlertState.sent ||
      alertState == RideCheckAlertState.sending;

  RideCheckSession copyWith({
    RideCheckStep? step,
    RideCheckRow? row,
    List<RideCheckAnswer>? answers,
    Map<String, RideCheckOptionId>? choices,
    String? note,
    RideCheckAlertState? alertState,
    String? alertId,
    bool? called112,
    String? Function()? callError,
    String? Function()? recordingNote,
  }) {
    return RideCheckSession(
      checkId: checkId,
      rideId: rideId,
      trigger: trigger,
      reason: reason,
      shownAt: shownAt,
      step: step ?? this.step,
      row: row ?? this.row,
      answers: answers ?? this.answers,
      choices: choices ?? this.choices,
      note: note ?? this.note,
      alertState: alertState ?? this.alertState,
      alertId: alertId ?? this.alertId,
      called112: called112 ?? this.called112,
      callError: callError == null ? this.callError : callError(),
      recordingNote: recordingNote == null
          ? this.recordingNote
          : recordingNote(),
    );
  }
}

/// Runs the rider's Ride check (RC1–RC5): watches the trip, opens the card,
/// records every answer on the trip, alerts the Movera safety team, and
/// keeps the card up until the rider answers.
class RideCheckController extends ChangeNotifier {
  RideCheckController({
    required RideCheckService service,
    required EmergencyCallService emergency,
    required SafetyAudioService audio,
    DateTime Function()? clock,
  }) : _service = service,
       _emergency = emergency,
       _audio = audio,
       _clock = clock ?? DateTime.now {
    _audio.addListener(_onRecordingInterrupted);
    _qaOwner = this;
    listenForRideCheckQa(_onQaSimulate);
  }

  /// The controller `moveraSimulateRideCheck` talks to (QA builds).
  static RideCheckController? _qaOwner;

  factory RideCheckController.forSafety(SafetyController safety) =>
      RideCheckController(
        service: safety.rideCheck,
        emergency: safety.emergency,
        audio: safety.audio,
      );

  static RideCheckController? _shared;
  static RideCheckController get shared =>
      _shared ??= RideCheckController.forSafety(SafetyController.shared);

  /// The shared controller if one was made; never creates one.
  static RideCheckController? get existing => _shared;

  @visibleForTesting
  static set sharedForTest(RideCheckController? controller) {
    _shared = controller;
  }

  static void resetShared() {
    final old = _shared;
    _shared = null;
    // rider-u202: a Ride check recording stops with the rider's data.
    old?._audio.discardForWipe();
    old?.dispose();
  }

  /// Whether live trip positions are checked against the triggers. The app
  /// turns it on at start-up; widget tests opt in, so a test that drives a
  /// made-up trip is not stopped by the card.
  static bool tripMonitoring = false;

  final RideCheckService _service;
  final EmergencyCallService _emergency;
  final SafetyAudioService _audio;
  final DateTime Function() _clock;

  RideCheckTripContext? _trip;
  RideCheckMonitor? _monitor;
  RideCheckSession? _session;
  String? _visibleRideId;
  final Set<String> _shown = {};

  /// rider-u192: triggers detected while another card was up. The monitor
  /// counts them as fired, so they wait here and open when that card
  /// closes instead of being lost.
  final List<({String rideId, RideCheckDetection hit})> _waiting = [];

  /// rider-u198: checks the rider answered. Their final save can still be
  /// queued behind a slow alert, so the saved event is not resolved yet and
  /// resume() must not bring them back.
  final Set<String> _closed = {};
  Future<void>? _queue;
  bool _disposed = false;

  RideCheckSession? get session => _session;

  /// The rider's switch and admin's triggers, as last read.
  RideCheckPolicy get policy => _service.policy();
  RideCheckTripContext? get trip => _trip;
  bool get recording => _audio.isRecording;

  /// rider-u212/u214: the card is coming to the front over the Safety Kit.
  /// A recording the rider started there carries on under the card's own
  /// control instead of stopping with the kit.
  void takeOverRecording() => _audio.handOver();
  DateTime? get recordingSince => _audio.active?.createdAt;

  /// The open card for [rideId], or null.
  RideCheckSession? sessionFor(String? rideId) {
    final id = rideId?.trim();
    final current = _session;
    if (id == null || id.isEmpty || current == null) return null;
    return current.rideId == id ? current : null;
  }

  /// True while the card is up for [rideId]: back does nothing.
  bool blocks(String? rideId) => sessionFor(rideId) != null;

  /// Waits for every save and send started so far (tests, sign-out).
  Future<void> settle() => _queue ?? Future<void>.value();

  // ---- The trip -----------------------------------------------------------

  void attachTrip(RideCheckTripContext trip, RideCheckPlan plan) {
    final sameRide = _trip?.rideId == trip.rideId;
    _trip = trip;
    if (!sameRide) _waiting.removeWhere((w) => w.rideId != trip.rideId);
    _parkOtherRide(trip.rideId);
    if (!sameRide || _monitor == null) {
      _monitor = RideCheckMonitor(
        settings: _service.policy().triggers,
        plan: plan,
      );
    }
    _visibleRideId = trip.rideId;
    _onQaSimulate();
  }

  /// rider-u194: a card still open for another ride belongs to a trip
  /// that ended without a completion screen (admin cancel, failed), where
  /// no screen can show it again. It is put aside, so it no longer blocks
  /// this trip's Ride checks. Its event stays unanswered on the device, so
  /// that ride's own screen would bring it back.
  void _parkOtherRide(String rideId) {
    final current = _session;
    if (current == null || current.rideId == rideId) return;
    _session = null;
    AppLog.info(
      'safety.ridecheck.parked',
      extra: {'rideId': current.rideId, 'trigger': current.trigger.wire},
    );
    unawaited(_audio.stopIfRecording(reason: 'ride_check_parked'));
    // attachTrip runs while the trip screen builds.
    scheduleMicrotask(_changed);
  }

  /// The driver, status or route the alert should carry changed.
  void updateTrip(
    String rideId,
    RideCheckTripContext Function(RideCheckTripContext current) change,
  ) {
    final current = _trip;
    if (current == null || current.rideId != rideId) return;
    _trip = change(current);
  }

  /// The rider changed the route mid-trip.
  void replan(String rideId, RideCheckPlan plan) {
    if (_trip?.rideId != rideId) return;
    _monitor?.replan(plan);
  }

  /// The road route the map drew for the trip.
  void setPlannedRoute(String rideId, List<GeoPoint> points) {
    if (_trip?.rideId != rideId) return;
    _monitor?.setPlannedRoute(points);
  }

  /// The in-trip screen closed. An open card stays: the next screen for the
  /// same ride shows it.
  void detachTrip(String rideId) {
    if (_trip?.rideId != rideId) return;
    _monitor = null;
  }

  /// A live position during the trip.
  void addSample(String rideId, RideCheckSample sample) {
    if (!tripMonitoring || _trip?.rideId != rideId) return;
    final monitor = _monitor;
    if (monitor == null) return;
    _trip = _trip!.copyWith(
      lastLocation: sample.point,
      lastLocationAt: sample.at,
    );
    final policy = _service.policy();
    if (!policy.enabled) return;
    monitor.settings = policy.triggers;
    final hit = monitor.addSample(sample);
    if (hit != null) unawaited(_openDetected(rideId, hit));
  }

  /// rider-u56: the screen's live feed came back after an outage; the
  /// stop clock restarts now.
  void liveFeedResumed(String rideId) {
    if (!tripMonitoring || _trip?.rideId != rideId) return;
    _monitor?.feedResumed(_clock());
  }

  /// No new position for a while: checks the long stop against the clock,
  /// with the car still where it was last seen standing. The in-trip screen
  /// calls this on a timer while the live feed is up.
  void checkStill(String rideId) {
    if (!tripMonitoring || _trip?.rideId != rideId) return;
    final monitor = _monitor;
    if (monitor == null) return;
    final policy = _service.policy();
    if (!policy.enabled) return;
    monitor.settings = policy.triggers;
    final hit = monitor.checkStill(_clock());
    if (hit != null) unawaited(_openDetected(rideId, hit));
  }

  /// The trip ended at [end] (the car's last position).
  Future<RideCheckOpenResult> tripEnded(String rideId, GeoPoint end) async {
    if (!tripMonitoring) return RideCheckOpenResult.notMonitoring;
    final monitor = _monitor;
    if (monitor == null || _trip?.rideId != rideId) {
      return RideCheckOpenResult.noTrip;
    }
    final policy = _service.policy();
    if (!policy.enabled) return RideCheckOpenResult.riderOff;
    monitor.settings = policy.triggers;
    final hit = monitor.tripEnded(end);
    if (hit == null) return RideCheckOpenResult.noTrigger;
    return _openDetected(rideId, hit);
  }

  /// The trip ended and where it ended is known only in a moment: the live
  /// wire carried no driver position, so the trip screen asks the rider's
  /// own phone. [end] is asked only when the answer will be used (no GPS
  /// read for a trip Ride check does not watch); the monitor stays for it
  /// even when that screen closes meanwhile ([detachTrip]); null from
  /// [end] is no position, no check.
  Future<RideCheckOpenResult> tripEndedAt(
    String rideId,
    Future<GeoPoint?> Function() end,
  ) async {
    if (!tripMonitoring) return RideCheckOpenResult.notMonitoring;
    final monitor = _monitor;
    if (monitor == null || _trip?.rideId != rideId) {
      return RideCheckOpenResult.noTrip;
    }
    if (!_service.policy().enabled) return RideCheckOpenResult.riderOff;
    final point = await end();
    if (_trip?.rideId != rideId) return RideCheckOpenResult.noTrip;
    if (point == null) return RideCheckOpenResult.noTrigger;
    final policy = _service.policy();
    if (!policy.enabled) return RideCheckOpenResult.riderOff;
    monitor.settings = policy.triggers;
    final hit = monitor.tripEnded(point);
    if (hit == null) return RideCheckOpenResult.noTrigger;
    return _openDetected(rideId, hit);
  }

  /// Opens a trigger the monitor detected. When another card is up it waits
  /// for that card to close (rider-u192).
  Future<RideCheckOpenResult> _openDetected(
    String rideId,
    RideCheckDetection hit,
  ) async {
    final result = await open(hit.trigger, reason: hit.reason, rideId: rideId);
    if (result == RideCheckOpenResult.busy) {
      _waiting.add((rideId: rideId, hit: hit));
    }
    return result;
  }

  void _openWaiting(String rideId) {
    final index = _waiting.indexWhere((w) => w.rideId == rideId);
    if (index < 0) return;
    final next = _waiting.removeAt(index);
    unawaited(_openDetected(next.rideId, next.hit));
  }

  // ---- Demo ---------------------------------------------------------------

  /// Demo trip for [playDemo]: Stockholm C to Solna centrum.
  static const demoPlan = RideCheckPlan(
    pickup: GeoPoint(59.3303, 18.0586),
    destination: GeoPoint(59.3600, 18.0000),
    destinationLabel: 'Solna centrum',
  );

  /// Plays a made-up trip for [rideId] through the real monitor and admin's
  /// numbers, so the card opens exactly as on a live trip: the driver taps
  /// Finish more than `finishFarFromDropoffKm` from the drop-off
  /// ([RideCheckTrigger.droppedFar]), or the car stands still mid-trip for
  /// more than `longStopMinutes` ([RideCheckTrigger.longStop]). The live
  /// trip, if any, is not touched.
  Future<RideCheckOpenResult> playDemo(
    RideCheckTrigger trigger, {
    required String rideId,
  }) async {
    final policy = _service.policy();
    final settings = policy.triggers;
    // rider-u193: the demo shows only the trigger it names; with the
    // off-route check on, a long stop of 14+ minutes on the short demo trip
    // first read as "longer than expected" and opened the off-route card.
    final monitor = RideCheckMonitor(
      settings: settings.copyWith(offRouteEnabled: false),
      plan: demoPlan,
    );
    RideCheckDetection? hit;
    switch (trigger) {
      case RideCheckTrigger.droppedFar:
        // Finish 600 m past admin's distance, due north of the drop-off.
        final meters = settings.finishFarFromDropoffKm * 1000 + 600;
        hit = monitor.tripEnded(
          GeoPoint(
            demoPlan.destination.latitude + meters / 111320,
            demoPlan.destination.longitude,
          ),
        );
      case RideCheckTrigger.longStop:
        // Halfway along the trip, standing still one minute past admin's
        // time.
        const stop = GeoPoint(59.3450, 18.0300);
        final start = _clock().toUtc().subtract(
          Duration(minutes: settings.longStopMinutes + 1),
        );
        final seconds = (settings.longStopMinutes + 1) * 60;
        for (var s = 0; s <= seconds && hit == null; s += 5) {
          hit = monitor.addSample(
            RideCheckSample(
              point: stop,
              at: start.add(Duration(seconds: s)),
            ),
          );
        }
      case RideCheckTrigger.offRoute:
      case RideCheckTrigger.possibleCrash:
        return open(trigger, rideId: rideId, again: true);
    }
    if (hit == null) {
      if (!policy.enabled) return RideCheckOpenResult.riderOff;
      if (!settings.isOn(trigger)) return RideCheckOpenResult.triggerOff;
      return RideCheckOpenResult.noTrigger;
    }
    return open(hit.trigger, reason: hit.reason, rideId: rideId, again: true);
  }

  // ---- Opening -------------------------------------------------------------

  /// Opens the card for [trigger] unless the rider or Movera turned it off,
  /// another card is up, or it already opened for this trip.
  Future<RideCheckOpenResult> open(
    RideCheckTrigger trigger, {
    RideCheckReason reason = const RideCheckReason(),
    String? rideId,
    bool again = false,
  }) async {
    final id = (rideId ?? _visibleRideId ?? _trip?.rideId)?.trim();
    if (id == null || id.isEmpty) return RideCheckOpenResult.noTrip;
    if (_session != null) return RideCheckOpenResult.busy;
    final policy = _service.policy();
    if (!policy.enabled) return RideCheckOpenResult.riderOff;
    if (!policy.triggers.isOn(trigger)) return RideCheckOpenResult.triggerOff;
    final key = '$id|${trigger.name}';
    if (!again && _shown.contains(key)) return RideCheckOpenResult.alreadyShown;
    _shown.add(key);
    final destination = _trip?.rideId == id ? _trip?.destination?.label : null;
    final full = RideCheckReason(
      distanceMeters: reason.distanceMeters,
      stoppedMinutes: reason.stoppedMinutes,
      longerPercent: reason.longerPercent,
      place: reason.place,
      destinationLabel: reason.destinationLabel ?? destination,
    );
    final session = RideCheckSession(
      checkId: 'rc_${newRequestId()}',
      rideId: id,
      trigger: trigger,
      reason: full,
      shownAt: _clock().toUtc(),
    );
    _session = session;
    AppLog.info(
      'safety.ridecheck.opened',
      extra: {'rideId': id, 'trigger': trigger.wire},
    );
    _changed();
    _enqueue('open', () async {
      await _service.open(
        eventId: session.checkId,
        rideId: id,
        trigger: trigger,
        at: session.shownAt,
        reason: full,
      );
    });
    return RideCheckOpenResult.shown;
  }

  /// A screen for [rideId] is showing: bring back a card the rider had not
  /// answered (the app was closed or reloaded), and open a queued QA check.
  Future<void> resume(String rideId) async {
    final id = rideId.trim();
    if (id.isEmpty) return;
    _visibleRideId = id;
    _onQaSimulate();
    if (_session != null) return;
    final RideCheckEvent? event;
    try {
      event = await _service.unanswered(id);
    } catch (error) {
      AppLog.warning(
        'safety.ridecheck.resume_failed',
        extra: {'rideId': id, 'error': '$error'},
      );
      return;
    }
    if (event == null || _session != null || _disposed) return;
    if (_closed.contains(event.eventId)) return;
    final record = RideCheckRecord.fromEvent(event);
    if (record == null) return;
    final alertId = event.payload['alertId'];
    // rider-u195: an alert that was asked for and never confirmed is
    // restored as failed (with its retry), never as sent or as none.
    final alertRequested = event.payload['alertRequested'] == true;
    _shown.add('$id|${record.trigger.name}');
    _session = RideCheckSession(
      checkId: record.checkId,
      rideId: id,
      trigger: record.trigger,
      reason: RideCheckReason.fromJson(event.payload['reason']),
      shownAt: record.shownAt,
      answers: record.answers,
      alertId: alertId is String ? alertId : null,
      alertState: alertId is String
          ? RideCheckAlertState.sent
          : alertRequested
          ? RideCheckAlertState.failed
          : RideCheckAlertState.none,
      called112: record.answers.any(
        (answer) => answer.kind == RideCheckAnswerKind.call112,
      ),
    );
    _changed();
  }

  // ---- Answers -------------------------------------------------------------

  /// "I'm OK": saved to the trip, and the card closes.
  void imOk() {
    final current = _session;
    if (current == null) return;
    _close(
      current.copyWith(
        answers: [...current.answers, RideCheckAnswer.ok(_clock())],
      ),
    );
  }

  /// Opens the phone dialer with 112. Movera never calls; the rider does.
  /// Calling counts as an answer and alerts the safety team.
  Future<void> call112() async {
    final current = _session;
    if (current == null) return;
    String? failure;
    try {
      await _emergency.callEmergencyNumber();
    } on EmergencyCallException catch (error) {
      failure = error.message;
    } catch (error) {
      failure = L10n.current.rcDialerFailed;
      AppLog.warning(
        'safety.ridecheck.dialer_failed',
        extra: {'error': '$error'},
      );
    }
    final latest = _session;
    if (latest == null || latest.checkId != current.checkId) return;
    final alreadyCalled = latest.answers.any(
      (answer) => answer.kind == RideCheckAnswerKind.call112,
    );
    // rider-81: 'Called 112' is saved only when the dialer opened; the
    // alert goes out either way.
    _session = latest.copyWith(
      called112: true,
      callError: () => failure,
      answers: alreadyCalled || failure != null
          ? latest.answers
          : [...latest.answers, RideCheckAnswer.call112(_clock())],
    );
    _sendAlert();
  }

  /// A row under "Or tell us what happened". Red rows alert at once (RC4).
  void chooseRow(RideCheckRowId id) {
    final current = _session;
    if (current == null || current.step != RideCheckStep.main) return;
    final row = current.rows.where((r) => r.id == id).firstOrNull;
    if (row == null) return;
    _session = current.copyWith(
      step: RideCheckStep.followUp,
      row: row,
      answers: [...current.answers, RideCheckAnswer.row(row, _clock())],
    );
    if (row.red) {
      _sendAlert();
    } else {
      _changed();
    }
  }

  /// An answer to a follow-up question. "Yes" or "Not sure" updates the
  /// alert already sent for this check (RC4).
  void choose(String questionId, RideCheckOptionId optionId) {
    final current = _session;
    final question = current?.row?.followUp.question(questionId);
    final option = question?.option(optionId);
    if (current == null || question == null || option == null) return;
    if (current.choices[questionId] == optionId) return;
    _session = current.copyWith(
      choices: {...current.choices, questionId: optionId},
      answers: [
        for (final answer in current.answers)
          if (!(answer.kind == RideCheckAnswerKind.question &&
              answer.id == questionId))
            answer,
        RideCheckAnswer.question(question, option, _clock()),
      ],
    );
    if (option.updatesAlert && current.alertState != RideCheckAlertState.none) {
      _sendAlert();
    } else {
      _changed();
    }
  }

  void setNote(String text) {
    final current = _session;
    if (current == null) return;
    final trimmed = text.length > 280 ? text.substring(0, 280) : text;
    _session = current.copyWith(note: trimmed);
  }

  /// Done: everything is saved to the trip and the card closes.
  void done() {
    final current = _session;
    if (current == null) return;
    if (current.answers.isEmpty) return;
    final note = current.note.trim();
    _close(
      current.copyWith(
        answers: [
          ...current.answers,
          if (note.isNotEmpty) RideCheckAnswer.note(note, _clock()),
        ],
      ),
    );
  }

  /// Sends the alert again after it failed.
  void retryAlert() {
    final current = _session;
    if (current == null || current.alertState != RideCheckAlertState.failed) {
      return;
    }
    _sendAlert();
  }

  /// "Record audio · saved only on this phone" (RC5). The recording never
  /// leaves the phone and is not registered with Movera.
  Future<void> toggleRecording() async {
    final current = _session;
    if (current == null) return;
    if (_audio.isRecording) {
      String note;
      try {
        await _audio.stop();
        note = L10n.current.rcRecordingSaved;
      } on SafetyAudioException catch (error) {
        note = error.message;
      }
      _setRecordingNote(current.checkId, note);
      return;
    }
    String? note;
    try {
      await _audio.start(rideId: current.rideId, deviceOnly: true);
    } on SafetyAudioException catch (error) {
      note = switch (error.code) {
        'UNSUPPORTED' => L10n.current.rcRecordingUnsupported,
        'MIC_DENIED' => L10n.current.rcAllowMicrophone,
        _ => L10n.current.rcRecordingStartFailed,
      };
    } catch (error) {
      note = L10n.current.rcRecordingStartFailed;
      AppLog.warning(
        'safety.ridecheck.record_failed',
        extra: {'error': '$error'},
      );
    }
    _setRecordingNote(current.checkId, note);
  }

  /// rider-u199: the OS interrupted the card's recording and it was
  /// stopped and saved, so the card stops counting "Recording m:ss".
  void _onRecordingInterrupted() {
    final current = _session;
    if (current == null) return;
    _setRecordingNote(
      current.checkId,
      _audio.lastInterruptionSaved == false
          ? L10n.current.audioSaveFailed
          : L10n.current.rcRecordingSaved,
    );
  }

  void _setRecordingNote(String checkId, String? note) {
    final latest = _session;
    if (latest == null || latest.checkId != checkId) {
      _changed();
      return;
    }
    _session = latest.copyWith(recordingNote: () => note);
    _changed();
  }

  // ---- Sending -------------------------------------------------------------

  RideCheckSubmission _submission(
    RideCheckSession session, {
    required bool alert,
    bool isFinal = false,
  }) {
    final trip = _trip;
    return RideCheckSubmission(
      checkId: session.checkId,
      trigger: session.trigger,
      shownAt: session.shownAt,
      answers: session.answers,
      reason: session.reason,
      context: trip != null && trip.rideId == session.rideId
          ? trip
          : RideCheckTripContext(rideId: session.rideId),
      alert: alert,
      alertId: session.alertId,
      isFinal: isFinal,
    );
  }

  void _sendAlert() {
    final current = _session;
    if (current == null) return;
    _session = current.copyWith(alertState: RideCheckAlertState.sending);
    _changed();
    final checkId = current.checkId;
    _enqueue('alert', () async {
      final latest = _session;
      if (latest == null || latest.checkId != checkId) return;
      RideCheckAlertState state;
      String? alertId;
      try {
        final receipt = await _service.submitAnswers(
          _submission(latest, alert: true),
        );
        alertId = receipt.alertId;
        state = receipt.alerted
            ? RideCheckAlertState.sent
            : RideCheckAlertState.failed;
      } catch (error) {
        state = RideCheckAlertState.failed;
        AppLog.warning(
          'safety.ridecheck.alert_failed',
          extra: {'checkId': checkId, 'error': '$error'},
        );
      }
      final after = _session;
      if (after == null || after.checkId != checkId) return;
      _session = after.copyWith(alertState: state, alertId: alertId);
      _changed();
    });
  }

  void _close(RideCheckSession closing) {
    _session = null;
    _closed.add(closing.checkId);
    AppLog.info(
      'safety.ridecheck.answered',
      extra: {
        'rideId': closing.rideId,
        'trigger': closing.trigger.wire,
        'answers': closing.answers.length,
      },
    );
    _changed();
    unawaited(_audio.stopIfRecording(reason: 'ride_check_closed'));
    final submission = _submission(
      closing,
      alert: closing.alertState != RideCheckAlertState.none,
      isFinal: true,
    );
    // rider-u197: saved on the device now. Queued behind a slow alert, a
    // reload before it ran brought the closed card back without its answer.
    unawaited(
      _service.keepAnswers(submission).catchError((Object error) {
        AppLog.warning(
          'safety.ridecheck.keep.failed',
          extra: {'error': '$error'},
        );
      }),
    );
    _enqueue('close', () async {
      await _service.submitAnswers(submission);
      try {
        await _service.resolve(
          RideCheckEvent(
            eventId: closing.checkId,
            rideId: closing.rideId,
            type: closing.trigger.eventType,
            at: closing.shownAt,
          ),
        );
      } finally {
        // The trip's details can show the saved answers now.
        _changed();
      }
    });
    _openWaiting(closing.rideId);
  }

  /// Writes run one after another, so an update never overtakes the alert
  /// it updates.
  void _enqueue(String what, Future<void> Function() job) {
    Future<void> run() async {
      try {
        await job();
      } catch (error) {
        AppLog.warning(
          'safety.ridecheck.$what.failed',
          extra: {'error': '$error'},
        );
      }
    }

    final previous = _queue;
    _queue = previous == null ? run() : previous.then((_) => run());
  }

  // ---- QA -----------------------------------------------------------------

  void _onQaSimulate() {
    final raw = pendingRideCheckType();
    if (raw == null) return;
    final rideId = _visibleRideId ?? _trip?.rideId;
    // Stays queued until a ride screen is showing.
    if (rideId == null) return;
    final detail = _qaDetail(pendingRideCheckDetail());
    clearPendingRideCheck();
    final trigger = parseRideCheckTrigger(raw) ?? RideCheckTrigger.longStop;
    unawaited(
      open(
        trigger,
        reason: _qaReason(trigger, detail),
        rideId: rideId,
        again: true,
      ).then((result) {
        AppLog.info(
          'safety.ridecheck.qa',
          extra: {'trigger': trigger.wire, 'result': result.name},
        );
      }),
    );
  }

  Map<String, dynamic> _qaDetail(String? raw) {
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : const {};
    } catch (_) {
      return const {};
    }
  }

  RideCheckReason _qaReason(
    RideCheckTrigger trigger,
    Map<String, dynamic> detail,
  ) {
    final given = RideCheckReason.fromJson(detail);
    final settings = _service.policy().triggers;
    return switch (trigger) {
      RideCheckTrigger.droppedFar => RideCheckReason(
        distanceMeters:
            given.distanceMeters ??
            settings.finishFarFromDropoffKm * 1000 + 400,
        destinationLabel: given.destinationLabel,
      ),
      RideCheckTrigger.longStop => RideCheckReason(
        stoppedMinutes: given.stoppedMinutes ?? settings.longStopMinutes,
        place: given.place,
      ),
      RideCheckTrigger.offRoute =>
        given.longerPercent != null
            ? RideCheckReason(longerPercent: given.longerPercent)
            : RideCheckReason(
                distanceMeters:
                    given.distanceMeters ?? settings.offRouteKm * 1000 + 400,
              ),
      RideCheckTrigger.possibleCrash => const RideCheckReason(),
    };
  }

  void _changed() {
    if (_disposed) return;
    notifyListeners();
    final current = _session;
    reportRideCheckSnapshot(
      jsonEncode({
        'open': current != null,
        if (current != null) ...{
          'rideId': current.rideId,
          'trigger': current.trigger.wire,
          'step': current.step.name,
          'row': current.row?.wire,
          'answers': current.answers.length,
          'alert': current.alertState.name,
          'called112': current.called112,
        },
      }),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _audio.removeListener(_onRecordingInterrupted);
    if (identical(_qaOwner, this)) {
      _qaOwner = null;
      listenForRideCheckQa(null);
    }
    super.dispose();
  }
}
