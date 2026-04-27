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

  // Getters
  static String? get sessionId => _sessionId;
  static String? get currentGame => _currentGame;
  static DateTime? get gameStartTime => _gameStartTime;
  static bool get isGameActive => _currentGame != null;

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

  // Reset all state (useful for logout or app reset)
  static void reset() {
    _sessionId = null;
    _currentGame = null;
    _gameStartTime = null;
    debugPrint('[SESSION_MANAGER] Session reset');
  }
}

