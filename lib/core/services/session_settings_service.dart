// session_settings_service.dart - holds the two comfort settings a pair picks at
// setup: how big the text is, and how fast/slow the games run (the pace).

import 'package:flutter/foundation.dart';

// Speed setting for a co-play session: relaxed (slower), standard, brisk (faster).
enum SessionPace { relaxed, standard, brisk }

// Adds a string id and a timing multiplier to each pace value.
extension SessionPaceX on SessionPace {
  String get id => name;

  // Higher = more time. 1.5 for relaxed, 1.0 for standard, 0.75 for brisk.
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

// Text size and pace for a paired session. Immutable; saved to Firestore for research.
@immutable
class SessionSettings {
  // 1.0 = normal system size.
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

// Holds the live session settings and notifies listeners when they change.
// Reset on logout so one participant's settings don't carry to the next.
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
