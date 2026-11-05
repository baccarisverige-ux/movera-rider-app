part of 'select_ride.dart';

/// 0 at the low stop → 1 at the middle stop ([mid] on the slide): the other
/// rides come in.
class _ListReveal extends Animatable<double> {
  const _ListReveal(this.mid);

  final double mid;

  @override
  double transform(double t) => mid <= 0 ? 1.0 : (t / mid).clamp(0.0, 1.0);
}

/// 0 at the middle stop → 1 at full: descriptions and badges.
class _DetailReveal extends Animatable<double> {
  const _DetailReveal(this.mid);

  final double mid;

  @override
  double transform(double t) => mid >= 1
      ? 0.0
      : Curves.easeOutCubic.transform(((t - mid) / (1 - mid)).clamp(0.0, 1.0));
}
