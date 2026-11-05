/// v0.18.38 §62 (fix job 8): the audio side of an in-app call. The
/// WebRTC engine ([WebRtcCallEngine]) talks to the phone's microphone and
/// speaker; tests use a fake. Audio goes peer to peer (or through TURN);
/// the server only relays the offer, the answer and the ICE candidates.
enum CallMediaState { connecting, connected, failed }

abstract class CallEngine {
  /// A local ICE candidate to send to the other side
  /// (`{candidate, sdpMid, sdpMLineIndex}`).
  void Function(Map<String, dynamic> candidate)? onCandidate;

  /// The connection to the other phone came up, or failed.
  void Function(CallMediaState state)? onMedia;

  /// Takes the microphone and sets up the connection with the server's
  /// STUN/TURN servers (`TripCall.ice.servers`).
  Future<void> open(List<Map<String, dynamic>> iceServers);

  /// The caller's SDP offer.
  Future<String> createOffer();

  /// The callee: the caller's offer in, this phone's SDP answer out.
  Future<String> acceptOffer(String sdp);

  /// The caller: the callee's answer.
  Future<void> acceptAnswer(String sdp);

  Future<void> addCandidate(Map<String, dynamic> candidate);
  Future<void> setMuted(bool muted);
  Future<void> setSpeaker(bool on);

  /// Hangs up the audio and lets the microphone go.
  Future<void> close();
}
