// activity_logs.dart - records events ("things that happened") and uploads them
// to Firestore. Events wait on the phone when offline and upload later.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:cardio_care_quest/core/constants/firestore_paths.dart';

// One logged event: name, params, and when it happened.
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

  // Serialize to a plain map for saving/uploading.
  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'params': params,
        'occurredAt': occurredAt.toIso8601String(),
      };

  // Deserialize from a saved map.
  factory LogEvent.fromMap(Map<dynamic, dynamic> map) {
    return LogEvent(
      id: map['id'] as String,
      name: map['name'] as String,
      params: Map<String, dynamic>.from(map['params'] as Map),
      occurredAt: DateTime.parse(map['occurredAt'] as String),
    );
  }
}

// LoggingService - records events on the phone and uploads them to the cloud.
class LoggingService {
  static const String _boxName = 'event_queue';
  static const int _maxQueueSize = 500; // keep at most 500 waiting events
  static const int _batchSize = 100; // upload in chunks of 100

  // Retry interval for the periodic safety-net upload attempt.
  static const Duration _retryInterval = Duration(seconds: 15);

  final FirebaseFirestore _firestore;
  final Uuid _uuid = const Uuid();
  late Box _box;
  bool _isSyncing = false;
  Timer? _retryTimer;

  // How many events are waiting to be uploaded. The sync badge reads this.
  final ValueNotifier<int> pendingCount = ValueNotifier<int>(0);

  // True while an upload is in progress. Used to animate the sync badge.
  final ValueNotifier<bool> isSyncing = ValueNotifier<bool>(false);

  LoggingService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  // Set up storage and start watching for internet. Call once at startup.
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

    // Periodic safety-net: connectivity events are sometimes missed (especially
    // on the emulator), so we retry on a timer to keep the queue draining.
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

  // Stop the retry timer on shutdown.
  void dispose() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  // Update the pending-count number for the UI badge.
  void _refreshPendingCount() {
    if (!_box.isOpen) return;
    pendingCount.value = _box.length;
  }

  // Save one event on the phone, then try to upload it.
  Future<void> logEvent(
    String name, {
    Map<String, dynamic>? parameters,
    String? phone,
    String? userId,
  }) async {
    // If the queue is full, drop the oldest event to make room.
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

  // Upload waiting events in chunks. Deletes each chunk after it lands safely.
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
              _firestore.collection(FirestorePaths.telemetry).doc(event.id);

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
      // Upload failed (probably offline). Events stay on the phone for next retry.
      debugPrint('Activity log sync failed: $e');
    } finally {
      _isSyncing = false;
      isSyncing.value = false;
      _refreshPendingCount();
    }
  }

  // Return all events still waiting on the phone (for debugging).
  Future<List<dynamic>> getAllLogs() async {
    if (!_box.isOpen) return [];
    return _box.values.toList();
  }

  // Delete all events waiting on the phone.
  Future<void> clearLogs() async {
    if (_box.isOpen) {
      await _box.clear();
      _refreshPendingCount();
    }
  }

  // True if the phone has some kind of internet connection right now.
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

