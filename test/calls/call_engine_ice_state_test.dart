import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:movera_rider/features/calls/data/webrtc_call_engine.dart';
import 'package:movera_rider/features/calls/domain/call_engine.dart';

/// 2026-11-11 owner phone test ("keep write connecting and never start"):
/// the engine heard only the peer connection's connected / failed. ICE
/// "failed" / "disconnected" (the only states some phones report) never
/// reached the call, so it stayed on "Connecting…". Fail-before: no ICE
/// state handler; disconnected unknown.

class _FakePc extends Fake implements RTCPeerConnection {
  @override
  Function(RTCPeerConnectionState state)? onConnectionState;
  @override
  Function(RTCIceConnectionState state)? onIceConnectionState;
  @override
  Function(RTCIceCandidate candidate)? onIceCandidate;
  @override
  Function(RTCTrackEvent event)? onTrack;
  bool closed = false;
  @override
  Future<void> close() async => closed = true;
}

class _FakeMic extends Fake implements MediaStream {
  @override
  List<MediaStreamTrack> getAudioTracks() => const [];
  @override
  List<MediaStreamTrack> getTracks() => const [];
  @override
  Future<void> dispose() async {}
}

void main() {
  test('engine: ICE and peer-connection failed / disconnected / connected '
      'reach the session', () async {
    final pc = _FakePc();
    final heard = <CallMediaState>[];
    final engine = WebRtcCallEngine(
      peerConnection: (_) async => pc,
      microphone: (_) async => _FakeMic(),
    )..onMedia = heard.add;
    await engine.open(const []);
    pc.onIceConnectionState!(
      RTCIceConnectionState.RTCIceConnectionStateChecking,
    );
    pc.onIceConnectionState!(
      RTCIceConnectionState.RTCIceConnectionStateCompleted,
    );
    pc.onIceConnectionState!(
      RTCIceConnectionState.RTCIceConnectionStateDisconnected,
    );
    pc.onIceConnectionState!(RTCIceConnectionState.RTCIceConnectionStateFailed);
    pc.onConnectionState!(
      RTCPeerConnectionState.RTCPeerConnectionStateDisconnected,
    );
    pc.onConnectionState!(RTCPeerConnectionState.RTCPeerConnectionStateFailed);
    expect(heard, [
      CallMediaState.connected,
      CallMediaState.disconnected,
      CallMediaState.failed,
      CallMediaState.disconnected,
      CallMediaState.failed,
    ]);
    // Our own hang-up closes the connection: not reported as a failure.
    await engine.close();
    pc.onConnectionState!(RTCPeerConnectionState.RTCPeerConnectionStateClosed);
    expect(heard, hasLength(5));
    expect(pc.closed, isTrue);
  });
}
