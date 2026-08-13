// Tracks per-game completions so the launcher knows whether to show the
// feedback popup. Stored per game (not a single slot) because some games
// launch a second game on top, and the second one finishing must not erase
// the first game's completion signal.
class GameCompletionSignal {
  GameCompletionSignal._();

  static final Map<String, DateTime> _completedAt = {};

  // Called by the host when the player reaches the finish state.
  static void markCompleted(String gameId) {
    _completedAt[gameId] = DateTime.now();
  }

  // Called by the launcher after the game closes. Returns true only if this
  // game was finished recently (within 10 min), then clears the mark.
  static bool consume(String gameId) {
    final at = _completedAt.remove(gameId);
    return at != null &&
        DateTime.now().difference(at) < const Duration(minutes: 10);
  }
}
