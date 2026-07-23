// Unit tests for CardioCare Quest pure logic.
//
// The previous contents were the unmodified Flutter counter-app template,
// which referenced a non-existent package name (`cardiocarequest`) and a
// `MyApp` widget this project doesn't have — producing two compile errors.
// The real app root (`CardioCareQuest`) calls `Firebase.initializeApp` in
// `main()`, so it can't be pumped in a plain widget test without mocking the
// Firebase platform channels. These tests instead exercise pure, deterministic
// logic that needs no bindings.

import 'package:flutter_test/flutter_test.dart';

import 'package:cardio_care_quest/core/services/session_settings_service.dart';

void main() {
  group('SessionSettings', () {
    test('defaults to no text scaling and standard pace', () {
      const s = SessionSettings.standard;
      expect(s.textScale, 1.0);
      expect(s.pace, SessionPace.standard);
    });

    test('round-trips through toMap / fromMap', () {
      const original =
          SessionSettings(textScale: 1.6, pace: SessionPace.relaxed);
      final restored = SessionSettings.fromMap(original.toMap());
      expect(restored.textScale, 1.6);
      expect(restored.pace, SessionPace.relaxed);
    });

    test('fromMap tolerates null and malformed input', () {
      expect(SessionSettings.fromMap(null).textScale, 1.0);
      expect(SessionSettings.fromMap(const {}).pace, SessionPace.standard);
      expect(
        SessionSettings.fromMap(const {'textScale': 'oops', 'pace': 'nope'})
            .textScale,
        1.0,
      );
    });

    test('copyWith overrides only the given field', () {
      const s = SessionSettings.standard;
      expect(s.copyWith(textScale: 2.0).textScale, 2.0);
      expect(s.copyWith(textScale: 2.0).pace, SessionPace.standard);
    });
  });

  group('SessionPace', () {
    test('id round-trips via fromId', () {
      for (final pace in SessionPace.values) {
        expect(SessionPaceX.fromId(pace.id), pace);
      }
    });

    test('unknown id falls back to standard', () {
      expect(SessionPaceX.fromId('bogus'), SessionPace.standard);
      expect(SessionPaceX.fromId(null), SessionPace.standard);
    });

    test('relaxed allows more time than brisk', () {
      expect(SessionPace.relaxed.timeMultiplier,
          greaterThan(SessionPace.brisk.timeMultiplier));
      expect(SessionPace.standard.timeMultiplier, 1.0);
    });
  });
}
