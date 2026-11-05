import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:movera_rider/features/calls/domain/call_engine.dart';

/// [CallEngine] on flutter_webrtc: audio only, one peer connection.
/// Remote ICE candidates that come before the remote description are
/// kept and added once it is set.
class WebRtcCallEngine implements CallEngine {
  RTCPeerConnection? _pc;
  MediaStream? _local;
  bool _remoteSet = false;
  final List<RTCIceCandidate> _pending = [];

  @override
  void Function(Map<String, dynamic> candidate)? onCandidate;
  @override
  void Function(CallMediaState state)? onMedia;

  @override
  Future<void> open(List<Map<String, dynamic>> iceServers) async {
    final pc = await createPeerConnection({
      'iceServers': iceServers,
      'sdpSemantics': 'unified-plan',
    });
    _pc = pc;
    _local = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': false,
    });
    for (final track in _local!.getAudioTracks()) {
      await pc.addTrack(track, _local!);
    }
    pc.onIceCandidate = (c) {
      if (c.candidate == null) return;
      onCandidate?.call({
        'candidate': c.candidate,
        'sdpMid': c.sdpMid,
        'sdpMLineIndex': c.sdpMLineIndex,
      });
    };
    pc.onConnectionState = (state) {
      switch (state) {
        case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
          onMedia?.call(CallMediaState.connected);
        case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
          onMedia?.call(CallMediaState.failed);
        default:
          break;
      }
    };
  }

  @override
  Future<String> createOffer() async {
    final offer = await _pc!.createOffer({'offerToReceiveAudio': true});
    await _pc!.setLocalDescription(offer);
    return offer.sdp ?? '';
  }

  @override
  Future<String> acceptOffer(String sdp) async {
    await _setRemote(RTCSessionDescription(sdp, 'offer'));
    final answer = await _pc!.createAnswer({'offerToReceiveAudio': true});
    await _pc!.setLocalDescription(answer);
    return answer.sdp ?? '';
  }

  @override
  Future<void> acceptAnswer(String sdp) =>
      _setRemote(RTCSessionDescription(sdp, 'answer'));

  Future<void> _setRemote(RTCSessionDescription description) async {
    await _pc!.setRemoteDescription(description);
    _remoteSet = true;
    for (final c in _pending) {
      await _pc!.addCandidate(c);
    }
    _pending.clear();
  }

  @override
  Future<void> addCandidate(Map<String, dynamic> candidate) async {
    final c = RTCIceCandidate(
      candidate['candidate'] as String?,
      candidate['sdpMid'] as String?,
      (candidate['sdpMLineIndex'] as num?)?.toInt(),
    );
    if (_pc == null || !_remoteSet) {
      _pending.add(c);
      return;
    }
    await _pc!.addCandidate(c);
  }

  @override
  Future<void> setMuted(bool muted) async {
    for (final track in _local?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = !muted;
    }
  }

  @override
  Future<void> setSpeaker(bool on) => Helper.setSpeakerphoneOn(on);

  @override
  Future<void> close() async {
    for (final track in _local?.getTracks() ?? <MediaStreamTrack>[]) {
      await track.stop();
    }
    await _local?.dispose();
    await _pc?.close();
    _local = null;
    _pc = null;
  }
}
