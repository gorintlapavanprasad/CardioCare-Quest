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
}

