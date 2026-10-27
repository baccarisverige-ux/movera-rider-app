import 'package:movera_rider/core/utils/request_id.dart';
import 'package:movera_rider/features/safety/data/safety_store.dart';
import 'package:movera_rider/features/safety/data/sos_sender.dart';
import 'package:movera_rider/features/safety/domain/ride_check.dart';
import 'package:movera_rider/features/safety/domain/ride_check_record.dart';
import 'package:movera_rider/features/safety/domain/ride_check_trigger.dart';

class RideCheckService {
  RideCheckService({SafetyStore? store}) : _store = store ?? SafetyStore.shared;

  final SafetyStore _store;

  RideCheckPolicy policy() => _store.rideCheck;

  List<RideCheckEvent> events() => _store.rideCheckEvents;

  Future<List<RideCheckEvent>> refresh(String rideId) =>
      _store.refreshEvents(rideId);

  Future<RideCheckPolicy> setEnabled(bool enabled) =>
      _store.patchRideCheck(enabled);

  Future<RideCheckEvent> simulate({
    required RideCheckEventType type,
    String rideId = 'ride_qa',
    String? eventId,
    DateTime? at,
  }) {
    return _store.postEvent(
      RideCheckEvent(
        eventId: eventId ?? 'ev_${newRequestId()}',
        rideId: rideId,
        type: type,
        at: at ?? DateTime.now().toUtc(),
      ),
    );
  }

  Future<RideCheckEvent> unexpectedStop({String rideId = 'ride_qa'}) =>
      simulate(type: RideCheckEventType.unexpectedStop, rideId: rideId);

  Future<RideCheckEvent> routeDeviation({String rideId = 'ride_qa'}) =>
      simulate(type: RideCheckEventType.routeDeviation, rideId: rideId);

  /// The SOS to Movera (contract v0.7.0); false when the trip is not live.
  Future<bool> sos({required String rideId, SosPosition? position}) =>
      _store.sendSos(rideId, position: position);

  /// Posts the safety event for a Ride check card that just opened.
  Future<RideCheckEvent> open({
    required String eventId,
    required String rideId,
    required RideCheckTrigger trigger,
    required DateTime at,
    RideCheckReason reason = const RideCheckReason(),
  }) {
    return _store.postEvent(
      RideCheckEvent(
        eventId: eventId,
        rideId: rideId,
        type: trigger.eventType,
        at: at,
        payload: {
          'kind': rideCheckEventKind,
          'trigger': trigger.wire,
          'reason': reason.toJson(),
        },
      ),
    );
  }

  /// Saves the answers on this device only, without a send.
  Future<void> keepAnswers(RideCheckSubmission submission) =>
      _store.keepRideCheckAnswers(submission);

  /// RC4: sends the answers (and the alert, when they call for one).
  Future<RideCheckReceipt> submitAnswers(RideCheckSubmission submission) =>
      _store.submitRideCheckAnswers(submission);

  /// RC5: the trip's Ride checks, newest first, from this device.
  Future<List<RideCheckRecord>> records(String rideId) async {
    final events = await _store.cachedRideCheckEvents(rideId);
    final records = [
      for (final event in events) ?RideCheckRecord.fromEvent(event),
    ]..sort((a, b) => b.shownAt.compareTo(a.shownAt));
    return records;
  }

  /// A Ride check card left open for [rideId] (the app was closed or
  /// reloaded before the rider answered). It must come back.
  Future<RideCheckEvent?> unanswered(String rideId) async {
    RideCheckEvent? latest;
    for (final event in await _store.cachedRideCheckEvents(rideId)) {
      if (event.status == RideCheckStatus.resolved ||
          event.status == RideCheckStatus.stale) {
        continue;
      }
      if (latest == null || event.at.isAfter(latest.at)) latest = event;
    }
    return latest;
  }

  Future<RideCheckEvent> resolve(RideCheckEvent event) {
    return _store.respondEvent(
      rideId: event.rideId,
      eventId: event.eventId,
      action: 'resolved',
    );
  }
}
