class FirestorePaths {
  static const events = 'events';
  static const dataPoints = 'data_points';
  static const movementData = 'Movement Data';
  static const userData = 'userData';
  static const surveys = 'surveys';
  static const responses = 'responses';

  static const locationData = 'LocationData';
  static const checkData = 'CheckData';
  static const likertData = 'LikertData';
  static const gameStates = 'gameStates';
  static const dailyLogs = 'dailyLogs';

  /// Sub-collections of an individual `dailyLogs/{date}` doc. One doc per
  /// entry so participants can log multiple in a single day without
  /// overwriting prior ones. The daily-log doc itself only carries summary
  /// fields (last reading, daily totals).
  static const exercises = 'exercises';
  static const bpReadings = 'bpReadings';
  static const meals = 'meals';

  static const baselineSurvey = 'baseline_survey';

  /// Sub-collection on `userData/{uid}/` holding the participant's
  /// "Design Your Own Game" creations. Each doc is a custom personal
  /// goal (title, category, points reward) that the participant taps
  /// to complete; completions go through PointsHooks + TelemetryHooks
  /// the same as catalog games.
  static const customGames = 'customGames';

  /// Sub-collection on `userData/{uid}/` holding per-action game
  /// activity logs from hub-and-spoke games (Vascular Village's
  /// per-quest credits, etc.). Distinct from `surveys/` which is
  /// reserved for actual questionnaire submissions — putting game
  /// data under surveys conflates two research artefacts. Each doc:
  /// `{gameId, questId, pointsEarned, sessionId?, data?, createdAt}`.
  static const gameLogs = 'gameLogs';

  /// Single doc on `userData/{uid}/preferences/favorites` holding the
  /// participant's starred game IDs as an array. Stored on Firestore
  /// (not SharedPreferences) so favourites follow the participant
  /// across devices when they log in with the same Unique ID.
  static const preferences = 'preferences';
  static const favorites = 'favorites';
}

