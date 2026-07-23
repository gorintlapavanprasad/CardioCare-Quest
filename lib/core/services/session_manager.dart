import 'package:flutter/material.dart';

/// SessionManager - Tracks game state across the app
/// Mirrored from netguage for consistency
/// 
/// Usage:
///   SessionManager.startGame('Walk Buddy');
///   // ... game runs ...
///   SessionManager.endGame();

class SessionManager {
  static String? _sessionId;
  static String? _currentGame;
  static DateTime? _gameStartTime;

  // ── Paired-session state (participant + caregiver co-play) ──────────────
  // A paired session groups every write made while a participant and their
  // caregiver play together. It is the single source of truth read by the
  // telemetry layer, which stamps `pairedSessionId` onto every event.
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

  /// The current in-game step/passage, if a game is reporting it. Used by the
  /// caregiver view to attach "help given" markers to the right game moment.
  static String? get currentStep => _currentStep;
  static set currentStep(String? step) => _currentStep = step;

  /// Begin a paired session. Called by the joint-setup flow after login.
  /// Pass a pre-minted id (so the same id can be persisted to secure storage
  /// for cold-start resume) or let this generate one.
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

  /// Rehydrate paired-session state on cold-start resume without minting a
  /// new id.
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

  // Called when a game is launched
  // Mirrors netguage's SessionManager.startGame()
  static void startGame(String gameTitle) {
    _currentGame = gameTitle;
    _gameStartTime = DateTime.now();
    debugPrint('[SESSION_MANAGER] Game started: $_currentGame at $_gameStartTime');
  }

  // Called when a game ends
  // Mirrors netguage's SessionManager.endGame()
  static void endGame() {
    if (_currentGame != null && _gameStartTime != null) {
      final duration = DateTime.now().difference(_gameStartTime!);
      debugPrint('[SESSION_MANAGER] Game ended: $_currentGame (Duration: ${duration.inSeconds}s)');
    }
    _currentGame = null;
    _gameStartTime = null;
  }

  // Get game duration in seconds
  static int? getGameDuration() {
    if (_gameStartTime == null) return null;
    return DateTime.now().difference(_gameStartTime!).inSeconds;
  }

  // Reset all state (useful for logout or app reset). Also clears any paired
  // session so a stale pairedSessionId can't leak onto the next participant's
  // events.
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

