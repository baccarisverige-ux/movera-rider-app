/// Contract v0.18.148 (`sosPressTime.apps`): the "SOS not sent, call 112"
/// notice is kept on the phone until the rider closes it, so a locked phone,
/// the background or a restart still shows it. The screen layer only knows
/// this; where it is kept is the data layer's (`PrefsSosNotSentFlag`).
abstract interface class SosNotSentFlag {
  /// Keeps "an SOS was given up on".
  Future<void> keep();

  /// Whether a notice is still to be shown.
  Future<bool> kept();

  /// The rider closed the notice.
  Future<void> forget();
}
