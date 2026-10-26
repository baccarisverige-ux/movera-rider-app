class AntiAbuse {
  static bool impossibleTravel({
    required double meters,
    required Duration window,
    double maxMps = 55,
  }) {
    if (window.inMilliseconds <= 0) return true;
    return meters / (window.inMilliseconds / 1000) > maxMps;
  }
}
