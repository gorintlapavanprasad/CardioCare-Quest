import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

/// Generic Hive-backed write queue for Firestore.
///
/// Every research-grade write (BP, exercise, meal, medication, quest
/// completions, surveys, etc.) is enqueued here BEFORE hitting Firestore.
/// On a successful Firestore replay the entry is deleted from Hive. If the
/// device is offline (or Firestore rejects), the entry stays in Hive and is
/// retried whenever connectivity transitions back up or [syncToFirestore]
/// is called manually.
///
/// Goals:
///  * Survives app kill (Hive persists to disk).
///  * Preserves batch atomicity (each PendingBatch replays via WriteBatch).
///  * Encodes Firestore sentinels (`FieldValue.serverTimestamp`,
///    `FieldValue.increment`, `FieldValue.delete`) and `GeoPoint` so they
///    round-trip through Hive.
///  * `serverTimestamp()` is resolved to a client `Timestamp` AT QUEUE TIME so
///    research analyses get true event time even when sync is hours later.
///  * `increment()` is replayed as `FieldValue.increment` so it merges
///    correctly server-side.
class OfflineQueue {
  static const String _boxName = 'offline_write_queue';
  static const int _maxBatches = 1000;

  /// Safety-net retry interval. The primary sync trigger is the
  /// connectivity_plus stream; this timer just guarantees we don't get stuck
  /// if the OS / emulator silently drops a connectivity event (observed on
  /// Android emulator after toggling airplane mode). Cheap: it short-circuits
  /// on `_box.isEmpty`.
  static const Duration _retryInterval = Duration(seconds: 15);

  final FirebaseFirestore _firestore;
  final Uuid _uuid = const Uuid();
  late Box _box;
  bool _isSyncing = false;
  Timer? _retryTimer;

  /// Number of batches currently waiting to sync. Drives the dashboard badge.
  final ValueNotifier<int> pendingCount = ValueNotifier<int>(0);

  /// True while a sync attempt is in flight.
  final ValueNotifier<bool> isSyncing = ValueNotifier<bool>(false);

  OfflineQueue({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  Future<void> init() async {
    await Hive.initFlutter();
    _box = await Hive.openBox(_boxName);
    _refreshPendingCount();

    Connectivity().onConnectivityChanged.listen((result) {
      debugPrint('OfflineQueue: connectivity event $result');
      if (_hasConnection(result)) {
        syncToFirestore();
      }
    });

    // Periodic safety-net retry. Some devices/emulators don't reliably emit a
    // connectivity event on the offline→online transition, leaving the queue
    // stuck until the user opens the app and (per old code) had to long-press
    // the badge. This timer drains the queue automatically every 15 s as long
    // as there's something pending.
    _retryTimer?.cancel();
    _retryTimer = Timer.periodic(_retryInterval, (_) {
      if (_box.isOpen && _box.isNotEmpty && !_isSyncing) {
        debugPrint('OfflineQueue: periodic retry (${_box.length} pending)');
        syncToFirestore();
      }
    });

    await syncToFirestore();
    debugPrint('OfflineQueue initialized (${_box.length} pending)');
  }

  void dispose() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  void _refreshPendingCount() {
    if (!_box.isOpen) return;
    pendingCount.value = _box.length;
  }

  /// Enqueue a single write spec, replayed standalone (no batch atomicity).
  Future<void> enqueue(PendingOp op) => enqueueBatch([op]);

  /// Enqueue an atomic batch of writes. They will be replayed as a single
  /// Firestore [WriteBatch] on the next sync.
  Future<void> enqueueBatch(List<PendingOp> ops) async {
    if (ops.isEmpty) return;

    if (_box.length >= _maxBatches) {
      // FIFO eviction. Should be rare with 1000-batch headroom.
      final oldestKey = _box.keys.first;
      await _box.delete(oldestKey);
      debugPrint('OfflineQueue: max size hit, evicted oldest batch');
    }

    final batch = PendingBatch(
      id: _uuid.v4(),
      ops: ops,
      queuedAt: DateTime.now(),
    );
    await _box.put(batch.id, batch.toMap());
    _refreshPendingCount();
    debugPrint(
      'OfflineQueue: queued batch ${batch.id} with ${ops.length} op(s)',
    );

    // Best-effort sync. If offline, this no-ops; the connectivity listener
    // will pick it up later.
    unawaited(syncToFirestore());
  }

  Future<void> syncToFirestore() async {
    if (_isSyncing || _box.isEmpty) return;
    _isSyncing = true;
    isSyncing.value = true;

    try {
      final keys = _box.keys.toList();

      for (final key in keys) {
        final raw = _box.get(key);
        if (raw == null) continue;

        try {
          final batch = PendingBatch.fromMap(
            (raw as Map).cast<dynamic, dynamic>(),
          );
          final wb = _firestore.batch();
          for (final op in batch.ops) {
            final ref = _refFromPath(op.path);
            switch (op.type) {
              case PendingOpType.set:
                wb.set(
                  ref,
                  _decodePayload(op.data ?? const {}),
                  op.merge ? SetOptions(merge: true) : null,
                );
                break;
              case PendingOpType.update:
                wb.update(ref, _decodePayload(op.data ?? const {}));
                break;
              case PendingOpType.delete:
                wb.delete(ref);
                break;
            }
          }
          await wb.commit();
          await _box.delete(key);
          _refreshPendingCount();
          debugPrint('OfflineQueue: synced batch ${batch.id}');
        } catch (e) {
          // Leave the batch in the queue and stop the loop. Next connectivity
          // event (or manual call) will retry. We avoid skipping ahead so
          // that ordering is preserved per-document.
          debugPrint('OfflineQueue: batch sync failed, will retry: $e');
          break;
        }
      }
    } finally {
      _isSyncing = false;
      isSyncing.value = false;
      _refreshPendingCount();
    }
  }

  Future<void> clear() async {
    if (_box.isOpen) {
      await _box.clear();
      _refreshPendingCount();
    }
  }

  DocumentReference<Map<String, dynamic>> _refFromPath(String path) {
    // Path format: "collection/doc/sub/doc/..." with even segment count.
    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.length < 2 || segments.length.isOdd) {
      throw StateError('OfflineQueue: invalid document path: $path');
    }
    DocumentReference<Map<String, dynamic>>? ref;
    CollectionReference<Map<String, dynamic>> col =
        _firestore.collection(segments[0]);
    for (var i = 1; i < segments.length; i++) {
      if (i.isOdd) {
        ref = col.doc(segments[i]);
      } else {
        col = ref!.collection(segments[i]);
      }
    }
    return ref!;
  }

  /// Recursively walk a payload and turn type markers back into their real
  /// runtime objects (FieldValue, GeoPoint, Timestamp).
  Map<String, dynamic> _decodePayload(Map<dynamic, dynamic> input) {
    final out = <String, dynamic>{};
    input.forEach((key, value) {
      out[key.toString()] = _decodeValue(value);
    });
    return out;
  }

  dynamic _decodeValue(dynamic value) {
    if (value is Map) {
      final marker = value['__type'];
      if (marker == 'increment') {
        return FieldValue.increment(value['value'] as num);
      }
      if (marker == 'delete') {
        return FieldValue.delete();
      }
      if (marker == 'geopoint') {
        return GeoPoint(
          (value['lat'] as num).toDouble(),
          (value['lng'] as num).toDouble(),
        );
      }
      if (marker == 'timestamp') {
        return Timestamp.fromMillisecondsSinceEpoch(value['ms'] as int);
      }
      return _decodePayload(value);
    }
    if (value is List) {
      return value.map(_decodeValue).toList();
    }
    return value;
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

/// One operation inside a PendingBatch.
enum PendingOpType { set, update, delete }

class PendingOp {
  final PendingOpType type;
  final String path;
  final Map<String, dynamic>? data;
  final bool merge;

  const PendingOp.set(this.path, this.data, {this.merge = false})
      : type = PendingOpType.set;
  const PendingOp.update(this.path, this.data)
      : type = PendingOpType.update,
        merge = false;
  const PendingOp.delete(this.path)
      : type = PendingOpType.delete,
        data = null,
        merge = false;

  Map<String, dynamic> toMap() => {
        'type': type.name,
        'path': path,
        if (data != null) 'data': data,
        'merge': merge,
      };

  factory PendingOp.fromMap(Map<dynamic, dynamic> map) {
    final typeName = map['type'] as String;
    final type = PendingOpType.values.firstWhere((t) => t.name == typeName);
    final dataRaw = map['data'];
    return PendingOp._raw(
      type: type,
      path: map['path'] as String,
      data: dataRaw == null
          ? null
          : (dataRaw as Map).map(
              (k, v) => MapEntry(k.toString(), v),
            ),
      merge: (map['merge'] as bool?) ?? false,
    );
  }

  const PendingOp._raw({
    required this.type,
    required this.path,
    required this.data,
    required this.merge,
  });
}

class PendingBatch {
  final String id;
  final List<PendingOp> ops;
  final DateTime queuedAt;

  PendingBatch({
    required this.id,
    required this.ops,
    required this.queuedAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'queuedAt': queuedAt.toIso8601String(),
        'ops': ops.map((o) => o.toMap()).toList(),
      };

  factory PendingBatch.fromMap(Map<dynamic, dynamic> map) {
    return PendingBatch(
      id: map['id'] as String,
      queuedAt: DateTime.parse(map['queuedAt'] as String),
      ops: (map['ops'] as List)
          .map((o) => PendingOp.fromMap(o as Map<dynamic, dynamic>))
          .toList(),
    );
  }
}

/// Helpers used by callers to encode special values into Hive-safe markers.
/// Use these when building a PendingOp's `data` map.
abstract class OfflineFieldValue {
  /// Replays as `FieldValue.increment(value)` server-side.
  static Map<String, dynamic> increment(num value) =>
      {'__type': 'increment', 'value': value};

  /// Replays as `FieldValue.delete()` server-side.
  static Map<String, dynamic> delete() => {'__type': 'delete'};

  /// Resolves AT QUEUE TIME to a client Timestamp. Use this in preference to
  /// `FieldValue.serverTimestamp()` when the timestamp must reflect when the
  /// event happened on the device, not when it eventually synced. The returned
  /// marker round-trips through Hive and emerges as a `Timestamp` on replay.
  static Map<String, dynamic> nowTimestamp() => {
        '__type': 'timestamp',
        'ms': DateTime.now().millisecondsSinceEpoch,
      };

  static Map<String, dynamic> timestampFrom(DateTime dt) => {
        '__type': 'timestamp',
        'ms': dt.millisecondsSinceEpoch,
      };

  static Map<String, dynamic> geopoint(double lat, double lng) =>
      {'__type': 'geopoint', 'lat': lat, 'lng': lng};
}
