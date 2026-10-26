class FareRules {
  static double minimum(double catalog) => (catalog * 0.65).roundToDouble();

  /// Owner decision (2026-10-26): the rider may offer up to 2× the price,
  /// the server's `dispatch.raisePrice.maxFactor` (it was 1.8× here).
  static const maxFactor = 2.0;

  static double maximum(double catalog) =>
      (catalog * maxFactor).roundToDouble();

  static bool allowsTotal({
    required double total,
    required double catalog,
  }) {
    return total >= minimum(catalog) && total <= maximum(catalog);
  }

  static double nudge({
    required double current,
    required double catalog,
    required int delta,
  }) {
    return (current + delta)
        .clamp(minimum(catalog), maximum(catalog))
        .roundToDouble();
  }
}
