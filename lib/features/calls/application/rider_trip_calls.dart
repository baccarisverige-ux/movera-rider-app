import 'package:flutter/foundation.dart';
import 'package:movera_rider/core/logging/app_log.dart';
import 'package:movera_rider/features/calls/data/webrtc_call_engine.dart';
import 'package:movera_rider/features/calls/domain/call_engine.dart';
import 'package:movera_rider/features/calls/domain/trip_call_session.dart';

/// v0.18.38 §62 (fix job 8, contract.json#inAppCalls; owner G15
/// 2026-11-05 "In-app calls only", "Both rider and driver"): the rider's
/// in-app calls. Holds the one call of this phone ([current]); the trip
/// stream's `call_*` events come in through [receive]; a `call_ringing`
/// for the rider becomes [incoming] and [onIncoming] opens the call screen.
/// Nothing of a call is kept on the phone.
class RiderTripCalls {
  RiderTripCalls({required CallApi api, CallEngine Function()? engine})
    : _api = api,
      _engine = engine ?? WebRtcCallEngine.new;

  /// The app's hub on the live wire (set in di.dart); null in the demo.
  static RiderTripCalls? instance;

  final CallApi _api;
  final CallEngine Function() _engine;
  static const _side = 'rider';

  TripCallSession? current;
  final ValueNotifier<TripCallSession?> incoming = ValueNotifier(null);

  /// Opens the call screen for a driver's call (the app root sets it).
  void Function(TripCallSession session)? onIncoming;

  TripCallSession outgoing(String tripId) {
    final session = TripCallSession.outgoing(
      api: _api,
      engine: _engine(),
      tripId: tripId,
      side: _side,
    );
    _hold(session);
    return session;
  }

  void _hold(TripCallSession session) {
    current = session;
    session.addListener(() {
      if (session.over && identical(current, session)) current = null;
      if (session.over && identical(incoming.value, session)) {
        incoming.value = null;
      }
    });
  }

  /// A `call_*` event of a trip stream (`call` = CallView; for
  /// `call_signal` the relayed signal).
  void receive(String tripId, String kind, Map<String, dynamic> payload) {
    final now = current;
    if (now != null && !now.over) {
      if (payload['callId'] == now.callId) {
        now.receive(kind, payload);
        return;
      }
      if (kind == 'call_ringing' && payload['to'] == _side) {
        final id = payload['callId'];
        if (id is String) _api.end(id, 'declined').catchError((Object _) {});
      }
      return;
    }
    if (kind != 'call_ringing' || payload['to'] != _side) return;
    try {
      final session = TripCallSession.incoming(
        api: _api,
        engine: _engine(),
        call: IncomingCall.fromJson(payload),
        side: _side,
        ice: const [],
      );
      _hold(session);
      incoming.value = session;
      onIncoming?.call(session);
    } on TypeError {
      AppLog.warning('trip_call.event_unreadable');
    }
  }
}
