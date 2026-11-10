import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// The app's own short sounds (made for Movera, no outside files):
/// `assets/sounds/chat_message.wav` for a new chat message (§78
/// `chat.sound`) and `assets/sounds/call_ring.wav`, looped while an
/// in-app call rings on this phone (§62: calls always ring).
///
/// Every call is safe to make anywhere: a browser that blocks sound
/// before the first tap, or a phone without audio, simply stays quiet.
abstract class TonePlayer {
  /// One short sound.
  Future<void> playOnce(String asset);

  /// [asset] again and again until [stop].
  Future<void> loop(String asset);
  Future<void> stop();
  Future<void> dispose();
}

abstract final class AppTones {
  static const String chatMessage = 'sounds/chat_message.wav';
  static const String callRing = 'sounds/call_ring.wav';

  /// Tests put a fake here; else a new [AudioTonePlayer].
  @visibleForTesting
  static TonePlayer Function()? debugCreate;

  static TonePlayer create() => debugCreate?.call() ?? AudioTonePlayer();

  static TonePlayer? _chat;

  /// The new-message sound (one shared player).
  static Future<void> playChatMessage() async {
    try {
      await (_chat ??= create()).playOnce(chatMessage);
    } catch (_) {
      // Autoplay blocked (web) or no audio: the message still shows.
    }
  }

  @visibleForTesting
  static void debugReset() => _chat = null;
}

/// [TonePlayer] on `audioplayers`; calls run one after the other.
class AudioTonePlayer implements TonePlayer {
  AudioTonePlayer({@visibleForTesting AudioPlayer Function()? create})
    : _create = create ?? AudioPlayer.new;

  final AudioPlayer Function() _create;
  AudioPlayer? _audio;
  bool _closed = false;
  Future<void> _queue = Future<void>.value();

  Future<void> _then(Future<void> Function(AudioPlayer a) op) {
    final next = _queue.then((_) async {
      if (_closed) return;
      await op(_audio ??= _create());
    });
    _queue = next.catchError((Object _) {});
    return _queue;
  }

  @override
  Future<void> playOnce(String asset) => _then((a) async {
    await a.stop();
    await a.setReleaseMode(ReleaseMode.stop);
    await a.play(AssetSource(asset));
  });

  @override
  Future<void> loop(String asset) => _then((a) async {
    await a.setReleaseMode(ReleaseMode.loop);
    await a.play(AssetSource(asset));
  });

  @override
  Future<void> stop() => _then((a) => a.stop());

  @override
  Future<void> dispose() {
    final last = _queue.then((_) async {
      final a = _audio;
      _audio = null;
      await a?.dispose();
    });
    _closed = true;
    _queue = last.catchError((Object _) {});
    return _queue;
  }
}

/// Rings while [isRinging] says so (an incoming call not yet answered,
/// declined, missed or failed) and stops for good after [dispose].
class CallRingtone {
  CallRingtone({TonePlayer? player}) : _player = player ?? AppTones.create();

  final TonePlayer _player;
  bool _on = false;
  bool _closed = false;

  bool get ringing => _on;

  /// Starts or stops the ring to match [ringing].
  void update(bool ringing) {
    if (_closed || ringing == _on) return;
    _on = ringing;
    unawaited(
      (ringing ? _player.loop(AppTones.callRing) : _player.stop()).catchError(
        (Object _) {},
      ),
    );
  }

  void dispose() {
    update(false);
    _closed = true;
    unawaited(_player.dispose().catchError((Object _) {}));
  }
}
