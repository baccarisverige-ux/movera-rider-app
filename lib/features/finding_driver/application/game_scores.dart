import 'package:shared_preferences/shared_preferences.dart';

/// Owner 2026-11-23: the searching games keep their best score on this
/// phone only (never sent anywhere).
abstract final class GameScores {
  static const String quizKey = 'movera.game.quiz.best.v1';
  static const String puzzleKey = 'movera.game.puzzle.best.v1';

  /// Keeps [score] under [key] when it beats the stored one ([lowerWins]:
  /// fewer is better).
  static Future<void> keepBest(
    String key,
    int score, {
    bool lowerWins = false,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final best = prefs.getInt(key);
      final better = best == null || (lowerWins ? score < best : score > best);
      if (better) await prefs.setInt(key, score);
    } catch (_) {
      // A best score is a nicety.
    }
  }
}
