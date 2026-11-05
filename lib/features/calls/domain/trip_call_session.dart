import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:movera_rider/features/calls/domain/call_engine.dart';

/// v0.18.38 §62 (fix job 8, contract.json#inAppCalls): the server side of
/// a call (`POST /trips/{tripId}/call`, `/calls/{callId}/answer|end|signal`).
abstract class CallApi {
  Future<Map<String, dynamic>> start(String tripId);

  /// The `CallView` with `ice` (the callee's STUN/TURN servers).
  Future<Map<String, dynamic>> answer(String callId);
  Future<void> end(String callId, String reason);
  Future<void> signal(String callId, Map<String, dynamic> body);
}

/// A `call_ringing` the other side started (`CallView`).
class IncomingCall {
  const IncomingCall({
    required this.callId,
    required this.tripId,
    required this.from,
  });
  factory IncomingCall.fromJson(Map<String, dynamic> json) => IncomingCall(
    callId: json['callId'] as String,
    tripId: json['tripId'] as String,
    from: json['from'] as String,
  );
  final String callId;
  final String tripId;
  final String from;
}

enum TripCallState { calling, ringing, connecting, connected, ended, failed }

/// One in-app call on this phone (owner G15 2026-11-05: "In-app calls
/// only", "Both rider and driver", "Just 'Call failed'"). The caller sends
/// the offer once the other side answered; the callee answers the offer.
/// Every failure ends in [TripCallState.failed]; the screen then says only
/// "Call failed". Nothing of the call is kept on the phone.
class TripCallSession extends ChangeNotifier {
  TripCallSession.outgoing({
    required CallApi api,
    required CallEngine engine,
    required this.tripId,
    required this.side,
  }) : _api = api,
       _engine = engine,
       outgoingCall = true,
       _state = TripCallState.calling;

  TripCallSession.incoming({
    required CallApi api,
    required CallEngine engine,
    required IncomingCall call,
    required this.side,
    required List<Map<String, dynamic>> ice,
  }) : _api = api,
       _engine = engine,
       outgoingCall = false,
       tripId = call.tripId,
       callId = call.callId,
       _ice = ice,
       _state = TripCallState.ringing;

  final CallApi _api;
  final CallEngine _engine;
  final String tripId;

  /// `driver` or `rider`: this phone's side.
  final String side;
  final bool outgoingCall;
  String? callId;
  List<Map<String, dynamic>> _ice = const [];
  TripCallState _state;
  bool _muted = false;
  bool _speaker = false;
  bool _engineOpen = false;

  TripCallState get state => _state;
  bool get muted => _muted;
  bool get speaker => _speaker;
  bool get over =>
      _state == TripCallState.ended || _state == TripCallState.failed;

  void _set(TripCallState next) {
    if (over) return;
    _state = next;
    notifyListeners();
  }

  Future<void> _openEngine() async {
    if (_engineOpen) return;
    _engineOpen = true;
    _engine.onCandidate = (candidate) {
      final id = callId;
      if (id == null || over) return;
      unawaited(
        _api
            .signal(id, {'type': 'ice', 'candidate': candidate})
            .catchError((Object _) {}),
      );
    };
    _engine.onMedia = (media) {
      if (media == CallMediaState.connected) _set(TripCallState.connected);
      if (media == CallMediaState.failed) unawaited(_fail());
    };
    await _engine.open(_ice);
  }

  /// The caller: asks the server for the call and gets the microphone ready.
  Future<void> start() async {
    final Map<String, dynamic> answer;
    try {
      answer = await _api.start(tripId);
    } catch (_) {
      await _fail();
      return;
    }
    await begin(answer);
  }

  /// The caller, with the server's `TripCall` already in hand.
  Future<void> begin(Map<String, dynamic> answer) async {
    try {
      if (answer['mode'] != 'in_app' || answer['callId'] is! String) {
        throw StateError('not an in-app call');
      }
      callId = answer['callId'] as String;
      final ice = answer['ice'];
      final servers = ice is Map ? ice['servers'] : null;
      _ice = servers is List
          ? [for (final s in servers) Map<String, dynamic>.from(s as Map)]
          : const [];
      await _openEngine();
    } catch (_) {
      await _fail();
    }
  }

  /// The callee taps Answer.
  Future<void> answer() async {
    final id = callId;
    if (id == null || _state != TripCallState.ringing) return;
    try {
      _set(TripCallState.connecting);
      final answered = await _api.answer(id);
      final ice = answered['ice'];
      final servers = ice is Map ? ice['servers'] : null;
      if (servers is List) {
        _ice = [for (final s in servers) Map<String, dynamic>.from(s as Map)];
      }
      await _openEngine();
    } catch (_) {
      await _fail();
    }
  }

  Future<void> decline() => _endWith('declined', TripCallState.ended);
  Future<void> hangUp() => _endWith('hangup', TripCallState.ended);

  Future<void> _fail() => _endWith('failed', TripCallState.failed);

  Future<void> _endWith(String reason, TripCallState next) async {
    if (over) return;
    final id = callId;
    _state = next;
    notifyListeners();
    if (id != null) {
      try {
        await _api.end(id, reason);
      } catch (error) {
        debugPrint("trip_call.cleanup: $error");
      }
    }
    await _closeEngine();
  }

  Future<void> _closeEngine() async {
    try {
      await _engine.close();
    } catch (error) {
      debugPrint("trip_call.cleanup: $error");
    }
  }

  Future<void> toggleMute() async {
    _muted = !_muted;
    await _engine.setMuted(_muted);
    notifyListeners();
  }

  Future<void> toggleSpeaker() async {
    _speaker = !_speaker;
    await _engine.setSpeaker(_speaker);
    notifyListeners();
  }

  /// A `call_*` event of this trip's stream (`call` = CallView, or for
  /// `call_signal` the relayed signal).
  Future<void> receive(String kind, Map<String, dynamic> payload) async {
    if (over || payload['callId'] != callId) return;
    try {
      switch (kind) {
        case 'call_answered':
          if (!outgoingCall) return;
          _set(TripCallState.connecting);
          final offer = await _engine.createOffer();
          await _api.signal(callId!, {'type': 'offer', 'sdp': offer});
        case 'call_signal':
          if (payload['from'] == side) return;
          final type = payload['type'];
          if (type == 'offer' && !outgoingCall) {
            final answer = await _engine.acceptOffer(payload['sdp'] as String);
            await _api.signal(callId!, {'type': 'answer', 'sdp': answer});
          } else if (type == 'answer' && outgoingCall) {
            await _engine.acceptAnswer(payload['sdp'] as String);
          } else if (type == 'ice' && payload['candidate'] is Map) {
            await _engine.addCandidate(
              Map<String, dynamic>.from(payload['candidate'] as Map),
            );
          }
        case 'call_ended':
        case 'call_missed':
          final reason = payload['endedReason'];
          _state = reason == 'failed'
              ? TripCallState.failed
              : TripCallState.ended;
          notifyListeners();
          await _closeEngine();
      }
    } catch (_) {
      await _fail();
    }
  }
}
