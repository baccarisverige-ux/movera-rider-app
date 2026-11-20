import 'package:movera_rider/l10n/l10n.dart';

/// Contract v0.9.0 `contract.json#ratings.tags` (owner real-data decision,
/// part 3): one fixed list of tag codes, the same in every country. A rider
/// may give the driver these (`aboutDriver`); the words are the app's own.
abstract final class RatingTags {
  ///
  /// v0.18.147 (contract.json#driverProfile.compliments): great_service
  /// added; the six in the chip order of the driver profile.
  static const aboutDriver = <String>[
    'great_service',
    'knew_the_way',
    'friendly',
    'clean_car',
    'safe_driving',
    'good_music',
  ];

  /// `contract.json#ratings.tags.maxPerRating` (6 since v0.18.147).
  static const maxPerRating = 6;

  /// `RatingRequest.review` maxLength (v0.18.147).
  static const reviewMaxLength = 280;

  /// `RatingRequest.comment` maxLength.
  static const commentMaxLength = 2000;

  static bool isAllowed(String code) => aboutDriver.contains(code);

  /// v0.18.147: the owner's compliment words (Utmärkt service, Bra vägval,
  /// Trevligt samtal, Ren bil, Säker körning, Bra musik).
  static String label(AppLocalizations l, String code) => switch (code) {
    'great_service' => l.complimentGreatService,
    'knew_the_way' => l.complimentKnewTheWay,
    'friendly' => l.complimentFriendly,
    'clean_car' => l.complimentCleanCar,
    'safe_driving' => l.complimentSafeDriving,
    'good_music' => l.complimentGoodMusic,
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
    this.dontMatchAgain = false,
    this.review = '',
    this.showFirstName = true,
  });

  /// v0.18.147: the optional short review (shown after admin approval) and
  /// whether it carries the rider's first name (default) or Anonymous.
  final String review;
  final bool showFirstName;

  String? get sentReview {
    final text = review.trim();
    return text.isEmpty ? null : text;
  }

  /// Fix job 10 (v0.18.43 §64): "Don't match me with this driver again".
  final bool dontMatchAgain;

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
      '${stars.toStringAsFixed(1)}|${tags.join(',')}|${sentComment ?? ''}|${dontMatchAgain ? 'x' : ''}|${sentReview ?? ''}|${showFirstName ? '' : 'a'}';
}
