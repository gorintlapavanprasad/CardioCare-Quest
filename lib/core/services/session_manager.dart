import 'package:flutter/material.dart';

// session_manager.dart - tracks which game is open and whether a participant
// and caregiver are playing together. Other code reads this to tag data correctly.

// Static holder of the active game and paired-session state.
class SessionManager {
  static String? _sessionId;
  static String? _currentGame;
  static DateTime? _gameStartTime;

  // Paired-session state (participant + caregiver playing together).
  static String? _pairedSessionId;
  static String? _participantId;
  static String? _caregiverId;
  static String? _caregiverLabel;
  static String? _currentStep;

  // Getters
  static String? get sessionId => _sessionId;
  static String? get currentGame => _currentGame;
  static DateTime? get gameStartTime => _gameStartTime;
  static bool get isGameActive => _currentGame != null;

  static String? get pairedSessionId => _pairedSessionId;
  static String? get participantId => _participantId;
  static String? get caregiverId => _caregiverId;
  static String? get caregiverLabel => _caregiverLabel;
  static bool get isPaired => _pairedSessionId != null;

  // The current in-game passage. Used to tag caregiver-help events to the right moment.
  static String? get currentStep => _currentStep;
  static set currentStep(String? step) => _currentStep = step;

  // Start a paired session. Pass a pre-made id or let this generate one.
  static String startPairedSession({
    required String participantId,
    String? caregiverId,
    String? caregiverLabel,
    String? pairedSessionId,
  }) {
    _participantId = participantId;
    _caregiverId = caregiverId;
    _caregiverLabel = caregiverLabel;
    _pairedSessionId =
        pairedSessionId ?? 'pair_${participantId}_${DateTime.now().millisecondsSinceEpoch}';
    debugPrint('[SESSION_MANAGER] Paired session started: $_pairedSessionId '
        '(participant=$participantId, caregiver=$caregiverLabel)');
    return _pairedSessionId!;
  }

  // Restore a paired session on cold-start without creating a new id.
  static void restorePairedSession({
    required String pairedSessionId,
    required String participantId,
    String? caregiverId,
    String? caregiverLabel,
  }) {
    _pairedSessionId = pairedSessionId;
    _participantId = participantId;
    _caregiverId = caregiverId;
    _caregiverLabel = caregiverLabel;
    debugPrint('[SESSION_MANAGER] Paired session restored: $_pairedSessionId');
  }

  // End the paired session and clear all its info so it can't leak onto later data.
  static void endPairedSession() {
    debugPrint('[SESSION_MANAGER] Paired session ended: $_pairedSessionId');
    _pairedSessionId = null;
    _participantId = null;
    _caregiverId = null;
    _caregiverLabel = null;
    _currentStep = null;
  }

  // Sets the session ID (typically called once at app startup)
  static void setSessionId(String id) {
    _sessionId = id;
    debugPrint('[SESSION_MANAGER] Session ID set to $_sessionId');
  }

  // Called when a game is launched.
  static void startGame(String gameTitle) {
    _currentGame = gameTitle;
    _gameStartTime = DateTime.now();
    debugPrint('[SESSION_MANAGER] Game started: $_currentGame at $_gameStartTime');
  }

  // Called when a game ends.
  static void endGame() {
    if (_currentGame != null && _gameStartTime != null) {
      final duration = DateTime.now().difference(_gameStartTime!);
      debugPrint('[SESSION_MANAGER] Game ended: $_currentGame (Duration: ${duration.inSeconds}s)');
    }
    _currentGame = null;
    _gameStartTime = null;
  }

  // How long the current game has been running, in seconds (null if none).
  static int? getGameDuration() {
    if (_gameStartTime == null) return null;
    return DateTime.now().difference(_gameStartTime!).inSeconds;
  }

  // Reset all state on logout so nothing leaks to the next participant.
  static void reset() {
    _sessionId = null;
    _currentGame = null;
    _gameStartTime = null;
    _pairedSessionId = null;
    _participantId = null;
    _caregiverId = null;
    _caregiverLabel = null;
    _currentStep = null;
    debugPrint('[SESSION_MANAGER] Session reset');
  }
}

