import 'package:movera_rider/core/api/api_error.dart';

/// The rating was saved but the tip was refused: the screen says why and
/// sends only the tip next time.
class TipRefusedAfterRating implements Exception {
  const TipRefusedAfterRating(this.cause);

  final ApiError cause;

  @override
  String toString() => 'TipRefusedAfterRating($cause)';
}
