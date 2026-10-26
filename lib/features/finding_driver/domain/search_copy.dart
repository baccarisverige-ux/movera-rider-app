import 'package:movera_rider/l10n/l10n.dart';

/// Rotating search copy. Changes with elapsed time, not every few seconds.
class SearchCopy {
  const SearchCopy({required this.headline, required this.subtitle});

  final String headline;
  final String subtitle;

  @override
  bool operator ==(Object other) =>
      other is SearchCopy &&
      other.headline == headline &&
      other.subtitle == subtitle;

  @override
  int get hashCode => Object.hash(headline, subtitle);

  static const delayedAfter = Duration(seconds: 60);

  /// When the "raise your offer" card appears on a real backend. It has its
  /// own timer: the "taking longer than usual" copy still waits for
  /// [delayedAfter].
  static const priceBumpAfter = Duration(seconds: 45);

  /// The same card in demo builds, early enough to be seen before the demo
  /// driver is assigned.
  static const demoPriceBumpAfter = Duration(seconds: 5);
  static const rotateEvery = Duration(seconds: 12);

  static List<SearchCopy> get initial => [
    SearchCopy(
      headline: L10n.current.findingDriver,
      subtitle: L10n.current.searchCheckingNearby,
    ),
    SearchCopy(
      headline: L10n.current.searchCheckingForNearby,
      subtitle: L10n.current.searchUpdateOnAccept,
    ),
  ];

  static List<SearchCopy> get waiting => [
    SearchCopy(
      headline: L10n.current.searchBestMatch,
      subtitle: L10n.current.searchNothingToDo,
    ),
    SearchCopy(
      headline: L10n.current.searchCheckingMoreHeadline,
      subtitle: L10n.current.searchStillActive,
    ),
    SearchCopy(
      headline: L10n.current.searchHangTight,
      subtitle: L10n.current.searchCheckingMore,
    ),
  ];

  static List<SearchCopy> get delayed => [
    SearchCopy(
      headline: L10n.current.searchBusier,
      subtitle: L10n.current.searchUpdateOnAccept,
    ),
    SearchCopy(
      headline: L10n.current.searchTakingLonger,
      subtitle: L10n.current.searchNothingToDo,
    ),
    SearchCopy(
      headline: L10n.current.searchMoreRiders,
      subtitle: L10n.current.searchExpanding,
    ),
    SearchCopy(
      headline: L10n.current.searchExpandingHeadline,
      subtitle: L10n.current.searchStillActive,
    ),
  ];

  static bool isDelayed(int elapsedSeconds) =>
      elapsedSeconds >= delayedAfter.inSeconds;

  /// Copy is keyed off **phase-local** elapsed, not a global modulo.
  /// 0–19 uses the initial copy, 20–59 uses waiting copy, and 60+ uses
  /// delayed copy starting at delayed[0].
  static SearchCopy forElapsed(int elapsedSeconds) {
    if (elapsedSeconds >= delayedAfter.inSeconds) {
      final step =
          (elapsedSeconds - delayedAfter.inSeconds) ~/ rotateEvery.inSeconds;
      return delayed[step % delayed.length];
    }
    if (elapsedSeconds >= 20) {
      final step = (elapsedSeconds - 20) ~/ rotateEvery.inSeconds;
      return waiting[step % waiting.length];
    }
    final elapsed = elapsedSeconds <= 0 ? 0 : elapsedSeconds;
    final step = elapsed ~/ rotateEvery.inSeconds;
    return initial[step % initial.length];
  }
}
