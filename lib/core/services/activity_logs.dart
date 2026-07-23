// activity_logs.dart - keeps a simple list of "things that happened" (events)
// and sends them up to the cloud (Firestore).
//
// Events are saved on the phone first (in a Hive box), then uploaded. If there's
// no internet, they wait on the phone and get sent later. So logging never fails.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:cardio_care_quest/core/constants/firestore_paths.dart';

// One logged event: what happened (name), extra details (params), and when.
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

  // Turn this event into a plain map so it can be saved/uploaded.
  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'params': params,
        'occurredAt': occurredAt.toIso8601String(),
      };

  // Rebuild an event from a saved map (the reverse of toMap).
  factory LogEvent.fromMap(Map<dynamic, dynamic> map) {
    return LogEvent(
      id: map['id'] as String,
      name: map['name'] as String,
      params: Map<String, dynamic>.from(map['params'] as Map),
      occurredAt: DateTime.parse(map['occurredAt'] as String),
    );
  }
}

// LoggingService - the thing the app calls to record events. It stores them
// on the phone and keeps trying to upload them to the cloud.
class LoggingService {
  static const String _boxName = 'event_queue';
  static const int _maxQueueSize = 500; // keep at most 500 waiting events
  static const int _batchSize = 100; // upload in chunks of 100

  /// Safety-net retry interval - see OfflineQueue for rationale.
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

  // Set up storage and start listening for internet so we can upload. Call once.
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

    // Periodic safety-net - connectivity events are sometimes missed on the
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

  // Stop the retry timer. Call when shutting the service down.
  void dispose() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  // Update the "how many are waiting" number for the UI badge.
  void _refreshPendingCount() {
    if (!_box.isOpen) return;
    pendingCount.value = _box.length;
  }

  // Record one event: save it on the phone, then try to upload right away.
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

  // Upload all waiting events to the cloud, in chunks. Deletes each chunk from
  // the phone once it's safely uploaded. Skips out if already running or empty.
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
      // Upload failed (probably offline). Leave events on the phone and retry later.
      debugPrint('Activity log sync failed: $e');
    } finally {
      _isSyncing = false;
      isSyncing.value = false;
      _refreshPendingCount();
    }
  }

  // Return every event still waiting on the phone (for debugging/inspection).
  Future<List<dynamic>> getAllLogs() async {
    if (!_box.isOpen) return [];
    return _box.values.toList();
  }

  // Throw away all waiting events on the phone.
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

