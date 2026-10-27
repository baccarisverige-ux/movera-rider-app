import 'package:movera_rider/l10n/l10n.dart';

/// Contract v0.9.0 `contract.json#ratings.tags` (owner real-data decision,
/// part 3): one fixed list of tag codes, the same in every country. A rider
/// may give the driver these (`aboutDriver`); the words are the app's own.
abstract final class RatingTags {
  static const aboutDriver = <String>[
    'clean_car',
    'friendly',
    'safe_driving',
    'good_music',
    'knew_the_way',
  ];

  /// `contract.json#ratings.tags.maxPerRating`.
  static const maxPerRating = 5;

  /// `RatingRequest.comment` maxLength.
  static const commentMaxLength = 2000;

  static bool isAllowed(String code) => aboutDriver.contains(code);

  static String label(AppLocalizations l, String code) => switch (code) {
    'clean_car' => l.ratingTagCleanCar,
    'friendly' => l.ratingTagFriendly,
    'safe_driving' => l.ratingTagSafeDriving,
    'good_music' => l.ratingTagGoodMusic,
    'knew_the_way' => l.ratingTagKnewTheWay,
    _ => code,
  };
}

/// What the rider gives on the completion screen: whole stars, the tags they
/// picked and an optional comment.
class RatingFeedback {
  const RatingFeedback({
    required this.stars,
    this.tags = const <String>[],
    this.comment = '',
  });

  final double stars;
  final List<String> tags;
  final String comment;

  /// The comment as it is sent: trimmed, or null when empty.
  String? get sentComment {
    final text = comment.trim();
    return text.isEmpty ? null : text;
  }

  /// A stable text of the choice, for the idempotency intent.
  String get intent =>
      '${stars.toStringAsFixed(1)}|${tags.join(',')}|${sentComment ?? ''}';
}
