import 'package:flutter/foundation.dart';

/// Pace presets for a co-play session. Maps to game timers / watchdog
/// intervals and (via the bridge) Twine game timing. `standard` is the
/// existing behaviour, so a session that never chooses a pace is unchanged.
enum SessionPace { relaxed, standard, brisk }

extension SessionPaceX on SessionPace {
  String get id => name;

  /// Multiplier applied to game timing (higher = slower/more time).
  double get timeMultiplier => switch (this) {
        SessionPace.relaxed => 1.5,
        SessionPace.standard => 1.0,
        SessionPace.brisk => 0.75,
      };

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

  SessionSettings copyWith({double? textScale, SessionPace? pace}) =>
      SessionSettings(
        textScale: textScale ?? this.textScale,
        pace: pace ?? this.pace,
      );

  Map<String, dynamic> toMap() => {
        'textScale': textScale,
        'pace': pace.id,
      };

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
/// SharedPreferences) — must be reset on logout so one participant's chosen
/// text size doesn't carry to the next.
///
/// Modeled on [FavoritesService]: a private-constructor singleton exposing a
/// [ValueNotifier].
class SessionSettingsService {
  SessionSettingsService._();
  static final SessionSettingsService instance = SessionSettingsService._();

  final ValueNotifier<SessionSettings> settings =
      ValueNotifier<SessionSettings>(SessionSettings.standard);

  void apply(SessionSettings s) => settings.value = s;

  void reset() => settings.value = SessionSettings.standard;
}
