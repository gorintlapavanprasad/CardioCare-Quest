import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:cardio_care_quest/core/constants/firestore_paths.dart';

class LogEvent {
  final String id;
  final String name;
  final Map<String, dynamic> params;
  final DateTime occurredAt;

  LogEvent({
    required this.id,
    required this.name,
    required this.params,
    required this.occurredAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'params': params,
        'occurredAt': occurredAt.toIso8601String(),
      };

  factory LogEvent.fromMap(Map<dynamic, dynamic> map) {
    return LogEvent(
      id: map['id'] as String,
      name: map['name'] as String,
      params: Map<String, dynamic>.from(map['params'] as Map),
      occurredAt: DateTime.parse(map['occurredAt'] as String),
    );
  }
}

class LoggingService {
  static const String _boxName = 'event_queue';
  static const int _maxQueueSize = 500;
  static const int _batchSize = 100;

  /// Safety-net retry interval — see OfflineQueue for rationale.
  static const Duration _retryInterval = Duration(seconds: 15);

  final FirebaseFirestore _firestore;
  final Uuid _uuid = const Uuid();
  late Box _box;
  bool _isSyncing = false;
  Timer? _retryTimer;

  /// Live count of events queued locally and not yet synced to Firestore.
  /// Driven by the underlying Hive box length. UI components (e.g. the sync
  /// badge in the dashboard header) listen to this to surface queue health.
  final ValueNotifier<int> pendingCount = ValueNotifier<int>(0);

  /// Whether a sync attempt is currently in flight. Useful for animating the
  /// sync badge.
  final ValueNotifier<bool> isSyncing = ValueNotifier<bool>(false);

  LoggingService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  Future<void> init() async {
    await Hive.initFlutter();
    _box = await Hive.openBox(_boxName);
    _refreshPendingCount();

    Connectivity().onConnectivityChanged.listen((result) {
      debugPrint('LoggingService: connectivity event $result');
      if (_hasConnection(result)) {
        syncToFirestore();
      }
    });

    // Periodic safety-net — connectivity events are sometimes missed on the
    // Android emulator (and occasionally on real devices) when toggling
    // airplane mode. The badge would otherwise sit at a non-zero count until
    // the user manually long-pressed it. This keeps the queue draining.
    _retryTimer?.cancel();
    _retryTimer = Timer.periodic(_retryInterval, (_) {
      if (_box.isOpen && _box.isNotEmpty && !_isSyncing) {
        debugPrint('LoggingService: periodic retry (${_box.length} pending)');
        syncToFirestore();
      }
    });

    await syncToFirestore();
    debugPrint('LoggingService initialized');
  }

  void dispose() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  void _refreshPendingCount() {
    if (!_box.isOpen) return;
    pendingCount.value = _box.length;
  }

  Future<void> logEvent(
    String name, {
    Map<String, dynamic>? parameters,
    String? phone,
    String? userId,
  }) async {
    if (_box.length >= _maxQueueSize) {
      final oldestKey = _box.keys.first;
      await _box.delete(oldestKey);
    }

    final event = LogEvent(
      id: _uuid.v4(),
      name: name,
      params: {
        ...?parameters,
        'phone': ?phone,
        'userId': ?userId,
      },
      occurredAt: DateTime.now(),
    );

    await _box.put(event.id, event.toMap());
    _refreshPendingCount();
    debugPrint('Queued log event: $name');
    await syncToFirestore();
  }

  Future<void> syncToFirestore() async {
    if (_isSyncing || _box.isEmpty) return;
    _isSyncing = true;
    isSyncing.value = true;

    try {
      final keys = _box.keys.toList();

      for (var i = 0; i < keys.length; i += _batchSize) {
        final batchKeys = keys.skip(i).take(_batchSize).toList();
        final batch = _firestore.batch();

        for (final key in batchKeys) {
          final rawMap = _box.get(key);
          if (rawMap == null) continue;

          final event = LogEvent.fromMap(rawMap as Map<dynamic, dynamic>);
          final docRef =
              _firestore.collection(FirestorePaths.events).doc(event.id);

          batch.set(docRef, {
            ...event.toMap(),
            'syncedAt': FieldValue.serverTimestamp(),
          });
        }

        await batch.commit();
        await _box.deleteAll(batchKeys);
        _refreshPendingCount();
      }
    } catch (e) {
      debugPrint('Activity log sync failed: $e');
    } finally {
      _isSyncing = false;
      isSyncing.value = false;
      _refreshPendingCount();
    }
  }

  Future<List<dynamic>> getAllLogs() async {
    if (!_box.isOpen) return [];
    return _box.values.toList();
  }

  Future<void> clearLogs() async {
    if (_box.isOpen) {
      await _box.clear();
      _refreshPendingCount();
    }
  }

  bool _hasConnection(Object result) {
    if (result is ConnectivityResult) {
      return result != ConnectivityResult.none;
    }
    if (result is List<ConnectivityResult>) {
      return result.any((value) => value != ConnectivityResult.none);
    }
    return true;
  }
}

