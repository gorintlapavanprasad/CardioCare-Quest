// session_settings_service.dart - holds the two comfort settings a pair picks at
// setup: how big the text is, and how fast/slow the games run (the pace).

import 'package:flutter/foundation.dart';

/// Pace presets for a co-play session.
// The three speed choices: relaxed (slower), standard (normal), brisk (faster). Maps to game timers / watchdog
/// intervals and (via the bridge) Twine game timing. `standard` is the
/// existing behaviour, so a session that never chooses a pace is unchanged.
enum SessionPace { relaxed, standard, brisk }

// Extra helpers bolted onto SessionPace (its short id, and how it affects timing).
extension SessionPaceX on SessionPace {
  String get id => name;

  /// Multiplier applied to game timing (higher = slower/more time).
  double get timeMultiplier => switch (this) {
        SessionPace.relaxed => 1.5,
        SessionPace.standard => 1.0,
        SessionPace.brisk => 0.75,
      };

  // Turn a saved id back into a pace; default to standard if it's unknown.
  static SessionPace fromId(String? id) => SessionPace.values.firstWhere(
        (p) => p.name == id,
        orElse: () => SessionPace.standard,
      );
}

/// Joint-setup settings for a paired session: text size and pace. Immutable;
/// snapshotted into `pairedSessions/{id}.settings` for research analysis and
/// applied at runtime via [SessionSettingsService].
@immutable
class SessionSettings {
  /// Global text scale factor. 1.0 = system default (existing behaviour).
  final double textScale;
  final SessionPace pace;

  const SessionSettings({this.textScale = 1.0, this.pace = SessionPace.standard});

  static const SessionSettings standard = SessionSettings();

  // Make a copy with one or both settings changed (leaves the original alone).
  SessionSettings copyWith({double? textScale, SessionPace? pace}) =>
      SessionSettings(
        textScale: textScale ?? this.textScale,
        pace: pace ?? this.pace,
      );

  // Save these settings as a plain map (for storing in the cloud).
  Map<String, dynamic> toMap() => {
        'textScale': textScale,
        'pace': pace.id,
      };

  // Rebuild settings from a saved map; fall back to standard if it's missing.
  factory SessionSettings.fromMap(Map<String, dynamic>? map) {
    if (map == null) return standard;
    final rawScale = map['textScale'];
    return SessionSettings(
      textScale: (rawScale is num) ? rawScale.toDouble() : 1.0,
      pace: SessionPaceX.fromId(map['pace'] as String?),
    );
  }
}

/// Holds the live session settings in memory and notifies listeners so the
/// [MaterialApp.builder]'s text-scale override rebuilds. Session-scoped (NOT
/// SharedPreferences) - must be reset on logout so one participant's chosen
/// text size doesn't carry to the next.
///
/// Modeled on [FavoritesService]: a private-constructor singleton exposing a
/// [ValueNotifier].
class SessionSettingsService {
  SessionSettingsService._();
  static final SessionSettingsService instance = SessionSettingsService._();

  final ValueNotifier<SessionSettings> settings =
      ValueNotifier<SessionSettings>(SessionSettings.standard);

  // Switch to new settings; the UI listens and updates text size right away.
  void apply(SessionSettings s) => settings.value = s;

  // Go back to normal settings (call on logout so they don't carry to the next user).
  void reset() => settings.value = SessionSettings.standard;
}
