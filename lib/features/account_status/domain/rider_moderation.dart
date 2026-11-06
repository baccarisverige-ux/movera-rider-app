import 'package:flutter/foundation.dart';

/// Contract v0.18.29 `riderModeration` (A2) shown by the rider app from
/// v0.18.40 §64 (fix job 10, owner G16 Q16-1): warning = the rider rides and
/// sees a banner; paused = a full screen with the end date; banned = the
/// same screen without a date. Read from `GET /rider/profile`
/// (`Rider.moderation`) and from any 403 `account_suspended` (its
/// projection). Nothing here is about a blocked driver pair: that is never
/// shown (owner "Never told").
enum ModerationLevel { none, warning, paused, banned }

@immutable
class RiderModeration {
  const RiderModeration({required this.level, this.reason, this.until});

  static const RiderModeration none = RiderModeration(
    level: ModerationLevel.none,
  );

  /// What the app shows now; the gate listens to it.
  static final ValueNotifier<RiderModeration> current =
      ValueNotifier<RiderModeration>(none);

  final ModerationLevel level;
  final String? reason;
  final DateTime? until;

  bool get blocksRiding =>
      level == ModerationLevel.paused || level == ModerationLevel.banned;

  static RiderModeration fromJson(Object? json) {
    if (json is! Map) return none;
    final level = switch (json['level']) {
      'warning' => ModerationLevel.warning,
      'paused' => ModerationLevel.paused,
      'banned' => ModerationLevel.banned,
      _ => ModerationLevel.none,
    };
    final reason = json['reason'];
    final until = json['until'];
    return RiderModeration(
      level: level,
      reason: reason is String && reason.trim().isNotEmpty
          ? reason.trim()
          : null,
      until: level == ModerationLevel.paused && until is String
          ? DateTime.tryParse(until)?.toUtc()
          : null,
    );
  }

  /// The `moderation` of a served Rider (profile) or a 403 projection.
  static RiderModeration fromRider(Object? rider) =>
      rider is Map ? fromJson(rider['moderation'] ?? rider) : none;

  @override
  bool operator ==(Object other) =>
      other is RiderModeration &&
      other.level == level &&
      other.reason == reason &&
      other.until == until;

  @override
  int get hashCode => Object.hash(level, reason, until);
}
