import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

// offline_queue.dart - saves cloud writes to the phone first, then sends them
// when internet is available. Retries automatically on failure.

// persists to disk). Timestamps are captured at queue time so event times are
// accurate even when sync happens hours later.
// The queue itself: holds pending writes on the phone and pushes them to the cloud.
class OfflineQueue {
  static const String _boxName = 'offline_write_queue';
  static const int _maxBatches = 1000; // don't let the queue grow past 1000

  // Backup retry every 15s in case the connectivity event was silently dropped.
  static const Duration _retryInterval = Duration(seconds: 15);

  final FirebaseFirestore _firestore;
  final Uuid _uuid = const Uuid();
  late Box _box;
  bool _isSyncing = false;
  Timer? _retryTimer;

  // Drives the dashboard sync badge.
  final ValueNotifier<int> pendingCount = ValueNotifier<int>(0);

  // True while a sync is running.
  final ValueNotifier<bool> isSyncing = ValueNotifier<bool>(false);

  OfflineQueue({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  // ---- SETUP ----

  // Open the phone storage and start watching for internet so we can send. Call once.
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

    // Fallback timer - some devices miss the connectivity event.
    _retryTimer?.cancel();
    _retryTimer = Timer.periodic(_retryInterval, (_) {
      if (_box.isOpen && _box.isNotEmpty && !_isSyncing) {
        debugPrint('OfflineQueue: periodic retry (${_box.length} pending)');
        syncToFirestore();
      }
    });

    // Fire-and-forget initial sync so startup doesn't block on the network.
    unawaited(syncToFirestore());
    debugPrint('OfflineQueue initialized (${_box.length} pending)');
  }

  // Stop the retry timer. Call when shutting down.
  void dispose() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  // Update the "how many waiting" number for the UI badge.
  void _refreshPendingCount() {
    if (!_box.isOpen) return;
    pendingCount.value = _box.length;
  }

  // ---- ADDING TO THE QUEUE ----

  // Queue a single write.
  Future<void> enqueue(PendingOp op) => enqueueBatch([op]);

  // Queue a group of writes that must all succeed together (or all fail).
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

    // Try syncing now; the connectivity listener will retry if offline.
    unawaited(syncToFirestore());
  }

  // ---- SENDING TO THE CLOUD ----

  // Try to send every waiting batch, oldest first. Each one that succeeds is
  // deleted from the phone. If one fails, we stop and keep the rest for later.
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
          // Stop on failure so order is preserved; retry on next connectivity event.
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

  // Throw away everything in the queue (e.g. on logout).
  Future<void> clear() async {
    if (_box.isOpen) {
      await _box.clear();
      _refreshPendingCount();
    }
  }

  // ---- HELPERS: paths & encoding ----

  // Convert a path string like "collection/doc/sub/doc" into a Firestore reference.
  DocumentReference<Map<String, dynamic>> _refFromPath(String path) {
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

  // Walk a payload and convert "__type" markers back into real Firestore objects.
  Map<String, dynamic> _decodePayload(Map<dynamic, dynamic> input) {
    final out = <String, dynamic>{};
    input.forEach((key, value) {
      out[key.toString()] = _decodeValue(value);
    });
    return out;
  }

  // Convert one value: "__type" markers become real FieldValue/GeoPoint/Timestamp.
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

  // True if the phone has some internet right now.
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

// ---- DATA SHAPES ----

// The kind of write: create/overwrite (set), change fields (update), or remove (delete).
enum PendingOpType { set, update, delete }

// One write to do: what kind, which document (path), and the data.
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

  // Save this write as a plain map (so it can sit on the phone).
  Map<String, dynamic> toMap() => {
        'type': type.name,
        'path': path,
        if (data != null) 'data': data,
        'merge': merge,
      };

  // Rebuild a write from its saved map.
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

// A group of writes that get sent together as one all-or-nothing unit.
class PendingBatch {
  final String id;
  final List<PendingOp> ops;
  final DateTime queuedAt;

  PendingBatch({
    required this.id,
    required this.ops,
    required this.queuedAt,
  });

  // Save this batch as a plain map.
  Map<String, dynamic> toMap() => {
        'id': id,
        'queuedAt': queuedAt.toIso8601String(),
        'ops': ops.map((o) => o.toMap()).toList(),
      };

  // Rebuild a batch from its saved map.
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

// Helpers for encoding special Firestore values so they survive the Hive round-trip.
// Use these when building a PendingOp's data map.
abstract class OfflineFieldValue {
  // Replays as FieldValue.increment server-side.
  static Map<String, dynamic> increment(num value) =>
      {'__type': 'increment', 'value': value};

  // Replays as FieldValue.delete server-side.
  static Map<String, dynamic> delete() => {'__type': 'delete'};

  // Captures the current device time at queue time, not sync time.
  // This keeps timestamps accurate even when sync happens hours later.
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
