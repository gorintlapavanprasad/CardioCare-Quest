// A tiny signal shared between the game hosts and the game launcher.
//
// A game host calls markCompleted(...) the moment the player reaches the
// game's finish/success state. After the game screen closes, the launcher
// calls consume(...) to decide whether to show the short 4-question feedback
// popup.
//
// We remember completions PER GAME (a map of gameId -> when), not in a single
// slot. This matters because some games launch another game on top when they
// finish - e.g. Salt Sludge and DASH Diet auto-open the Daily Check-In, and
// Vascular Village opens Quiet Landscape. That second game finishing must not
// wipe the first game's completion, or the first game's feedback popup would
// never show.
class GameCompletionSignal {
  GameCompletionSignal._();

  // gameId -> the moment that game was last finished.
  static final Map<String, DateTime> _completedAt = {};

  // Called by a host when the player actually finishes a game.
  static void markCompleted(String gameId) {
    _completedAt[gameId] = DateTime.now();
  }

  // Called by the launcher after the game closes. Returns true (and forgets
  // this game's mark) only if THIS game was finished a short while ago, so a
  // normal early exit (no completion) never shows the popup.
  static bool consume(String gameId) {
    final at = _completedAt.remove(gameId);
    return at != null &&
        DateTime.now().difference(at) < const Duration(minutes: 10);
  }
}
