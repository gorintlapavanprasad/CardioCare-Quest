// health_service.dart - reads health data (heart rate, steps, blood oxygen, etc.)
// from Apple Health (iOS) or Health Connect (Android). Returns plain numbers;
// missing or denied data gives nulls, never a crash.

import 'package:flutter/foundation.dart';
import 'package:health/health.dart';

// Wraps the Health plugin. Call requestPermissions() once at startup, then
// captureSnapshot() whenever you need vitals. All fields can be null.
class HealthService {
  HealthService._();
  static final HealthService instance = HealthService._();

  // Health types we read. Same list on iOS and Android; the plugin maps them
  // to the right native types. Apple Watch on iOS, Wear OS on Android.
  static const List<HealthDataType> _readTypes = [
    HealthDataType.HEART_RATE,
    HealthDataType.RESTING_HEART_RATE,
    HealthDataType.HEART_RATE_VARIABILITY_SDNN,
    HealthDataType.STEPS,
    HealthDataType.ACTIVE_ENERGY_BURNED,
    HealthDataType.EXERCISE_TIME,
    HealthDataType.BLOOD_OXYGEN,
  ];

  // Read-only permissions for each type.
  static List<HealthDataAccess> get _readPermissions =>
      List.filled(_readTypes.length, HealthDataAccess.READ);

  bool _configured = false;
  bool _permissionsGranted = false;
  bool get permissionsGranted => _permissionsGranted;

  // ---- PERMISSIONS ----

  // One-time plugin setup.
  Future<void> _ensureConfigured() async {
    if (_configured) return;
    await Health().configure();
    _configured = true;
  }

  // Ask the OS for health permissions. Returns true if granted.
  // Safe to call multiple times; no-op if already granted.
  Future<bool> requestPermissions() async {
    try {
      await _ensureConfigured();

      final hasExisting = await Health().hasPermissions(
            _readTypes,
            permissions: _readPermissions,
          ) ??
          false;
      if (hasExisting) {
        _permissionsGranted = true;
        return true;
      }

      final granted = await Health().requestAuthorization(
        _readTypes,
        permissions: _readPermissions,
      );
      _permissionsGranted = granted;
      return granted;
    } catch (e) {
      debugPrint('HealthService.requestPermissions error: $e');
      _permissionsGranted = false;
      return false;
    }
  }

  // ---- SNAPSHOT ----
  // Grab current vitals. Time windows: HR last 30 min, resting HR/HRV last 24 h,
  // steps/energy/exercise today, blood oxygen last 6 h.
  // Returns an empty snapshot on error or missing permissions; never throws.
  Future<HealthSnapshot> captureSnapshot() async {
    final now = DateTime.now();
    final empty = HealthSnapshot(collectedAt: now);

    if (!_permissionsGranted) {
      // Try once - the user may have granted permission in Settings.
      final ok = await requestPermissions();
      if (!ok) return empty;
    }

    try {
      await _ensureConfigured();

      // Time windows for each data type.
      final startOfToday = DateTime(now.year, now.month, now.day);
      final last24h = now.subtract(const Duration(hours: 24));
      final last6h = now.subtract(const Duration(hours: 6));
      final last30m = now.subtract(const Duration(minutes: 30));

      double? heartRate;
      double? restingHeartRate;
      double? hrv;
      int? steps;
      double? activeEnergy;
      int? exerciseMinutes;
      double? bloodOxygen;

      // Latest reading for each type.
      final heartRatePoints = await _safeRead(
        type: HealthDataType.HEART_RATE,
        start: last30m,
        end: now,
      );
      heartRate = _latestNumeric(heartRatePoints);

      final restingHrPoints = await _safeRead(
        type: HealthDataType.RESTING_HEART_RATE,
        start: last24h,
        end: now,
      );
      restingHeartRate = _latestNumeric(restingHrPoints);

      final hrvPoints = await _safeRead(
        type: HealthDataType.HEART_RATE_VARIABILITY_SDNN,
        start: last24h,
        end: now,
      );
      hrv = _latestNumeric(hrvPoints);

      final bloodOxygenPoints = await _safeRead(
        type: HealthDataType.BLOOD_OXYGEN,
        start: last6h,
        end: now,
      );
      bloodOxygen = _latestNumeric(bloodOxygenPoints);

      // Daily totals from midnight to now.
      try {
        steps = await Health().getTotalStepsInInterval(startOfToday, now);
      } catch (e) {
        debugPrint('HealthService steps error: $e');
      }

      final activeEnergyPoints = await _safeRead(
        type: HealthDataType.ACTIVE_ENERGY_BURNED,
        start: startOfToday,
        end: now,
      );
      activeEnergy = _sumNumeric(activeEnergyPoints);

      final exercisePoints = await _safeRead(
        type: HealthDataType.EXERCISE_TIME,
        start: startOfToday,
        end: now,
      );
      final exerciseSum = _sumNumeric(exercisePoints);
      exerciseMinutes = exerciseSum?.round();

      return HealthSnapshot(
        heartRate: heartRate,
        restingHeartRate: restingHeartRate,
        heartRateVariability: hrv,
        stepsToday: steps,
        activeEnergyToday: activeEnergy,
        exerciseMinutesToday: exerciseMinutes,
        bloodOxygen: bloodOxygen,
        collectedAt: now,
      );
    } catch (e) {
      debugPrint('HealthService.captureSnapshot error: $e');
      return empty;
    }
  }

  // ---- HELPERS ----

  // Read one health type for a time range. Returns empty on error (so one bad
  // type doesn't break the whole snapshot). Removes duplicates.
  Future<List<HealthDataPoint>> _safeRead({
    required HealthDataType type,
    required DateTime start,
    required DateTime end,
  }) async {
    try {
      final data = await Health().getHealthDataFromTypes(
        types: [type],
        startTime: start,
        endTime: end,
      );
      return Health().removeDuplicates(data);
    } catch (e) {
      debugPrint('HealthService read error ($type): $e');
      return const [];
    }
  }

  // Get the most recent numeric value from a list of readings.
  double? _latestNumeric(List<HealthDataPoint> points) {
    if (points.isEmpty) return null;
    points.sort((a, b) => b.dateTo.compareTo(a.dateTo)); // newest first

    final value = points.first.value;
    if (value is NumericHealthValue) {
      return value.numericValue.toDouble();
    }
    return null;
  }

  // Sum all numeric values in a list (e.g. total calories today).
  double? _sumNumeric(List<HealthDataPoint> points) {
    if (points.isEmpty) return null;
    var sum = 0.0;
    var hadAny = false;
    for (final p in points) {
      final v = p.value;
      if (v is NumericHealthValue) {
        sum += v.numericValue.toDouble();
        hadAny = true;
      }
    }
    return hadAny ? sum : null;
  }
}

// ---- SNAPSHOT DATA ----

// Health numbers at one point in time. All fields are nullable (no data = null).
class HealthSnapshot {
  final double? heartRate; // bpm
  final double? restingHeartRate; // bpm
  final double? heartRateVariability; // ms (SDNN)
  final int? stepsToday;
  final double? activeEnergyToday; // kcal
  final int? exerciseMinutesToday;
  final double? bloodOxygen; // %
  final DateTime collectedAt;

  const HealthSnapshot({
    this.heartRate,
    this.restingHeartRate,
    this.heartRateVariability,
    this.stepsToday,
    this.activeEnergyToday,
    this.exerciseMinutesToday,
    this.bloodOxygen,
    required this.collectedAt,
  });

  // True if at least one field has data.
  bool get hasAnyData =>
      heartRate != null ||
      restingHeartRate != null ||
      heartRateVariability != null ||
      stepsToday != null ||
      activeEnergyToday != null ||
      exerciseMinutesToday != null ||
      bloodOxygen != null;

  // Firestore-ready map. Only includes non-null fields.
  Map<String, dynamic> toFirestore() {
    final out = <String, dynamic>{
      'collectedAt': collectedAt.toIso8601String(),
    };
    if (heartRate != null) out['heartRate'] = heartRate;
    if (restingHeartRate != null) out['restingHeartRate'] = restingHeartRate;
    if (heartRateVariability != null) {
      out['heartRateVariability'] = heartRateVariability;
    }
    if (stepsToday != null) out['stepsToday'] = stepsToday;
    if (activeEnergyToday != null) out['activeEnergyToday'] = activeEnergyToday;
    if (exerciseMinutesToday != null) {
      out['exerciseMinutesToday'] = exerciseMinutesToday;
    }
    if (bloodOxygen != null) out['bloodOxygen'] = bloodOxygen;
    return out;
  }
}
