class FareRules {
  static double minimum(double catalog) => (catalog * 0.65).roundToDouble();

  static double maximum(double catalog) => (catalog * 1.8).roundToDouble();

  static bool allowsTotal({required double total, required double catalog}) {
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
