import 'package:flutter/foundation.dart';
import 'package:health/health.dart';

/// Wraps the [Health] plugin so the rest of the app deals in plain Dart
/// types and doesn't have to know about HealthKit / Health Connect specifics.
///
/// Lifecycle:
///   1. [HealthService.instance.requestPermissions()] — call once early
///      (HomeTab.initState) to surface the OS permission dialog.
///   2. [HealthService.instance.captureSnapshot()] — call at meaningful
///      events (e.g. BP prompt save) to grab a vitals snapshot.
///
/// Both methods are best-effort: if permissions are denied or no data
/// exists for a type (e.g. user has no Apple Watch paired), the snapshot
/// fields are null. Callers should treat all fields as optional.
class HealthService {
  HealthService._();
  static final HealthService instance = HealthService._();

  /// Data types we read. Same set on iOS HealthKit and Android Health
  /// Connect — the plugin maps these to the right native types per
  /// platform. Apple Watch contributes most of these on iOS; Wear OS
  /// devices via Health Connect contribute on Android.
  static const List<HealthDataType> _readTypes = [
    HealthDataType.HEART_RATE,
    HealthDataType.RESTING_HEART_RATE,
    HealthDataType.HEART_RATE_VARIABILITY_SDNN,
    HealthDataType.STEPS,
    HealthDataType.ACTIVE_ENERGY_BURNED,
    HealthDataType.EXERCISE_TIME,
    HealthDataType.BLOOD_OXYGEN,
  ];

  static List<HealthDataAccess> get _readPermissions =>
      List.filled(_readTypes.length, HealthDataAccess.READ);

  bool _configured = false;
  bool _permissionsGranted = false;
  bool get permissionsGranted => _permissionsGranted;

  Future<void> _ensureConfigured() async {
    if (_configured) return;
    await Health().configure();
    _configured = true;
  }

  /// Trigger the OS permission flow. Returns true if the user granted
  /// access to at least one read type. Safe to call multiple times —
  /// subsequent calls are no-ops if already granted.
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

  /// Read a recent snapshot of Apple-Watch-friendly vitals.
  ///
  /// Time windows:
  ///  * heart rate — most recent reading in the last 30 min
  ///  * resting HR — most recent reading in the last 24 h
  ///  * HRV — most recent reading in the last 24 h
  ///  * steps / active energy / exercise minutes — totals for today
  ///    (device-local midnight to now)
  ///  * blood oxygen — most recent reading in the last 6 h
  ///
  /// Returns an empty snapshot if permissions aren't granted or the
  /// plugin throws; never throws to the caller.
  Future<HealthSnapshot> captureSnapshot() async {
    final now = DateTime.now();
    final empty = HealthSnapshot(collectedAt: now);

    if (!_permissionsGranted) {
      // Try once — the user may have granted permission in Settings.
      final ok = await requestPermissions();
      if (!ok) return empty;
    }

    try {
      await _ensureConfigured();

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

      // Most-recent helpers — pick the latest non-null reading in window.
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

      // Daily totals — use the plugin's aggregator helper.
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

  double? _latestNumeric(List<HealthDataPoint> points) {
    if (points.isEmpty) return null;
    points.sort((a, b) => b.dateTo.compareTo(a.dateTo));
    final value = points.first.value;
    if (value is NumericHealthValue) {
      return value.numericValue.toDouble();
    }
    return null;
  }

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

/// Plain-Dart snapshot of Apple-Watch-style vitals at a moment in time.
///
/// All numeric fields are nullable — null means "no data available" (no
/// permission, no paired device, no reading in the time window). Treat
/// every field as optional when consuming.
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

  bool get hasAnyData =>
      heartRate != null ||
      restingHeartRate != null ||
      heartRateVariability != null ||
      stepsToday != null ||
      activeEnergyToday != null ||
      exerciseMinutesToday != null ||
      bloodOxygen != null;

  /// Firestore-ready map. Only includes keys with non-null values, so
  /// the BP reading doc doesn't carry empty fields when no Watch is paired.
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
