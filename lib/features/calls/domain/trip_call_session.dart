import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:movera_rider/features/calls/domain/call_connect_rules.dart';
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
    this.connectTimeout,
  });
  factory IncomingCall.fromJson(Map<String, dynamic> json) => IncomingCall(
    callId: json['callId'] as String,
    tripId: json['tripId'] as String,
    from: json['from'] as String,
    connectTimeout: CallConnectRules.timeoutOf(json),
  );
  final String callId;
  final String tripId;
  final String from;

  /// v0.18.66 §87: `CallView.connectTimeoutSeconds` of `call_ringing`;
  /// null when the server sent none.
  final Duration? connectTimeout;
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
    Duration? connectTimeout,
    bool Function()? isTablet,
  }) : _api = api,
       _engine = engine,
       outgoingCall = true,
       _connectTimeout = connectTimeout ?? defaultConnectTimeout,
       _isTablet = isTablet ?? CallConnectRules.isTabletScreen,
       _state = TripCallState.calling;

  TripCallSession.incoming({
    required CallApi api,
    required CallEngine engine,
    required IncomingCall call,
    required this.side,
    required List<Map<String, dynamic>> ice,
    Duration? connectTimeout,
    bool Function()? isTablet,
  }) : _api = api,
       _engine = engine,
       outgoingCall = false,
       tripId = call.tripId,
       callId = call.callId,
       _ice = ice,
       _connectTimeout =
           call.connectTimeout ?? connectTimeout ?? defaultConnectTimeout,
       _isTablet = isTablet ?? CallConnectRules.isTabletScreen,
       _state = TripCallState.ringing;

  final CallApi _api;
  final CallEngine _engine;
  final String tripId;

  /// 2026-11-11 owner phone test ("keep write connecting and never
  /// start"): without a TURN relay the two phones may never reach each
  /// other, and the offer, the answer or the ICE candidates can be lost on
  /// the way (a dropped trip stream). Nothing then ever said "connected"
  /// or "failed", so the screen said "Connecting…" for ever. Now a call
  /// that is not connected [connectTimeout] after Answer (or after the
  /// link dropped) ends as failed: "Call failed" (owner G15).
  ///
  /// Contract v0.18.66 §87 (owner 2026-11-11, Rule 16): the limit is an
  /// admin setting the server sends with each call
  /// (`TripCall.connectTimeoutSeconds`, `CallView.connectTimeoutSeconds`);
  /// 25 s when it sends none (an older server), held to 10–60.
  static const defaultConnectTimeout = CallConnectRules.defaultTimeout;
  Duration _connectTimeout;
  Duration get connectTimeout => _connectTimeout;

  /// §87 "Tablet ON, phone OFF": read when the call first connects.
  final bool Function() _isTablet;

  /// The speaker was set once (the default on first connect, or the
  /// rider's own Speaker tap): later connects keep it.
  bool _speakerSet = false;

  /// §87 "Add hint": the call failed because the connect time limit ran
  /// out (also "Calling…" running out); the screen shows the hint under
  /// "Call failed".
  bool _connectTimedOut = false;
  bool get connectTimedOut => _connectTimedOut;

  /// The caller's "Calling…" also ends: the server ends an unanswered call
  /// after `ringSeconds`; if that event never reaches this phone, the call
  /// ends as failed [connectTimeout] after the ring time.
  static const defaultRingSeconds = 30;
  Timer? _guard;

  /// `driver` or `rider`: this phone's side.
  final String side;
  final bool outgoingCall;
  String? callId;
  List<Map<String, dynamic>> _ice = const [];
  TripCallState _state;
  bool _muted = false;
  bool _speaker = false;
  bool _engineOpen = false;

  /// 2026-11-11 owner phone test ("we cannot hear each other"): the other
  /// side's offer / answer / ICE could arrive while this phone was still
  /// taking the microphone (the first call shows Android's microphone
  /// question), so the SDP answer had no audio track or the engine was not
  /// there yet. Signals now wait until the engine is open.
  final Completer<void> _ready = Completer<void>();

  /// Signals are handled one at a time, in the order they came.
  Future<void> _signals = Future<void>.value();

  TripCallState get state => _state;
  bool get muted => _muted;
  bool get speaker => _speaker;
  bool get over =>
      _state == TripCallState.ended || _state == TripCallState.failed;

  void _set(TripCallState next) {
    if (over) return;
    if (next == TripCallState.connected) {
      _stopGuard();
      _speakerDefault();
    }
    // The connect time runs once the microphone is ours: the first call
    // shows Android's microphone question, which is not counted.
    if (next == TripCallState.connecting &&
        _ready.isCompleted &&
        (_state != TripCallState.connecting || _guard == null)) {
      _startGuard(connectTimeout);
    }
    _state = next;
    notifyListeners();
  }

  void _startGuard(Duration wait) {
    _guard?.cancel();
    _guard = Timer(wait, () {
      _guard = null;
      if (over || _state == TripCallState.connected) return;
      debugPrint('trip_call.connect_timeout: ${_state.name}');
      _connectTimedOut = true;
      unawaited(_fail());
    });
  }

  /// The first time the call connects: speaker ON on a tablet, OFF
  /// (earpiece) on a phone, unless the rider already chose with the
  /// Speaker button. A link that drops and comes back keeps his choice.
  /// Web: the engine's setSpeaker does nothing (the browser picks).
  void _speakerDefault() {
    if (_speakerSet) return;
    _speakerSet = true;
    _speaker = _isTablet();
    unawaited(_engine.setSpeaker(_speaker).catchError((Object _) {}));
  }

  void _stopGuard() {
    _guard?.cancel();
    _guard = null;
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
      if (over) return;
      switch (media) {
        case CallMediaState.connected:
          _set(TripCallState.connected);
        case CallMediaState.failed:
          unawaited(_fail());
        case CallMediaState.disconnected:
          // The link dropped: "Connecting…" again, and failed unless it
          // comes back within [connectTimeout].
          if (_state == TripCallState.connected) {
            _set(TripCallState.connecting);
          }
        case CallMediaState.connecting:
          break;
      }
    };
    try {
      await _engine.open(_ice);
    } finally {
      if (!_ready.isCompleted) _ready.complete();
    }
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
      _connectTimeout = CallConnectRules.timeoutOf(answer) ?? _connectTimeout;
      final ring = answer['ringSeconds'];
      final ice = answer['ice'];
      final servers = ice is Map ? ice['servers'] : null;
      _ice = servers is List
          ? [for (final s in servers) Map<String, dynamic>.from(s as Map)]
          : const [];
      await _openEngine();
      if (_state == TripCallState.calling) {
        _startGuard(
          Duration(seconds: ring is int ? ring : defaultRingSeconds) +
              connectTimeout,
        );
      }
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
      _connectTimeout = CallConnectRules.timeoutOf(answered) ?? _connectTimeout;
      final ice = answered['ice'];
      final servers = ice is Map ? ice['servers'] : null;
      if (servers is List) {
        _ice = [for (final s in servers) Map<String, dynamic>.from(s as Map)];
      }
      await _openEngine();
      if (_state == TripCallState.connecting && _guard == null) {
        _startGuard(connectTimeout);
      }
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
    _stopGuard();
    _state = next;
    notifyListeners();
    if (id != null) {
      try {
        await _api.end(id, reason);
      } catch (error) {
        debugPrint("trip_call.cleanup: $error");
      }
    }
    if (!_ready.isCompleted) _ready.complete();
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
    _speakerSet = true;
    _speaker = !_speaker;
    await _engine.setSpeaker(_speaker);
    notifyListeners();
  }

  /// A `call_*` event of this trip's stream (`call` = CallView, or for
  /// `call_signal` the relayed signal).
  Future<void> receive(String kind, Map<String, dynamic> payload) {
    if (over || payload['callId'] != callId) return Future<void>.value();
    if (kind == 'call_ended' || kind == 'call_missed') {
      return _receive(kind, payload);
    }
    final next = _signals.then((_) async {
      await _ready.future;
      await _receive(kind, payload);
    });
    _signals = next.catchError((Object _) {});
    return next;
  }

  Future<void> _receive(String kind, Map<String, dynamic> payload) async {
    if (over) return;
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
          _stopGuard();
          _state = reason == 'failed'
              ? TripCallState.failed
              : TripCallState.ended;
          notifyListeners();
          if (!_ready.isCompleted) _ready.complete();
          await _closeEngine();
      }
    } catch (_) {
      await _fail();
    }
  }
}
