// FavoritesService — per-participant set of favourited game IDs,
// backed by Firestore so favourites sync across devices.
//
// Stored as a single doc:
//   userData/{uid}/preferences/favorites
//   { gameIds: ["dog_quest", "bingo_bash", ...] }
//
// Reads stream live via Firestore snapshots so a star toggled on
// Device A is visible on Device B within seconds. Writes go through
// OfflineQueue using the same set/update pattern as the rest of the
// app, so toggling a star while offline still works.
//
// Was previously SharedPreferences-only — that meant stars were
// per-device. Participants opening the app on a second device with
// the same Unique ID saw an empty list. Migrated to Firestore so
// participants' favourites travel with them.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';

import '../constants/firestore_paths.dart';
import 'offline_queue.dart';

class FavoritesService {
  FavoritesService._();
  static final FavoritesService instance = FavoritesService._();

  /// Currently-loaded participant. `null` until [load] is called.
  String? _participantId;

  /// Live subscription to the Firestore favorites doc — replaces the
  /// earlier SharedPreferences cache. Cancelled when the participant
  /// changes (relog) or [clear] is called.
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;

  /// In-memory mirror of the latest snapshot. `ValueNotifier<Set<String>>`
  /// re-emits a *new* Set on each update so [ValueListenableBuilder]
  /// rebuilds reliably.
  final ValueNotifier<Set<String>> favorites =
      ValueNotifier<Set<String>>(<String>{});

  OfflineQueue get _queue => GetIt.instance<OfflineQueue>();

  /// Path of the favorites doc for [uid].
  String _docPath(String uid) =>
      '${FirestorePaths.userData}/$uid/${FirestorePaths.preferences}/${FirestorePaths.favorites}';

  /// Subscribe to the participant's favorites doc. Cheap to call
  /// repeatedly — re-subscribes only when the participant changes.
  Future<void> load(String participantId) async {
    if (participantId.isEmpty) return;
    if (_participantId == participantId && _sub != null) return;
    _participantId = participantId;
    await _sub?.cancel();

    final ref = FirebaseFirestore.instance.doc(_docPath(participantId));
    _sub = ref.snapshots().listen((snap) {
      final data = snap.data() ?? const <String, dynamic>{};
      final raw = data['gameIds'];
      Set<String> ids = <String>{};
      if (raw is List) {
        for (final v in raw) {
          if (v is String && v.isNotEmpty) ids.add(v);
        }
      }
      favorites.value = ids;
    }, onError: (e) {
      debugPrint('FavoritesService: snapshot error — $e');
    });
  }

  bool isFavorite(String gameId) => favorites.value.contains(gameId);

  /// Toggle a game's favourite state. Returns the new state.
  /// Optimistic — updates the in-memory notifier immediately so the
  /// UI flips state before the Firestore round-trip resolves; the
  /// snapshot listener will reconcile if the write fails.
  Future<bool> toggle(String gameId) async {
    final pid = _participantId;
    if (pid == null || pid.isEmpty) {
      debugPrint('FavoritesService.toggle: no participant loaded — skipping');
      return favorites.value.contains(gameId);
    }
    final current = Set<String>.from(favorites.value);
    final wasFavorite = current.contains(gameId);
    if (wasFavorite) {
      current.remove(gameId);
    } else {
      current.add(gameId);
    }
    // Local-first update for responsive UI.
    favorites.value = current;

    // Persist as a full overwrite of `gameIds`. The doc may not exist
    // on first toggle, so we use `set + merge: true` so the write
    // creates it and updates only this field on subsequent toggles.
    await _queue.enqueue(PendingOp.set(
      _docPath(pid),
      {
        'gameIds': current.toList(),
        'updatedAt': OfflineFieldValue.nowTimestamp(),
      },
      merge: true,
    ));
    return !wasFavorite;
  }

  /// Drop the in-memory cache and unsubscribe. Used when the
  /// participant logs out so the next participant on this device
  /// doesn't briefly see the previous user's favourites before their
  /// own snapshot loads.
  void clear() {
    _participantId = null;
    _sub?.cancel();
    _sub = null;
    favorites.value = <String>{};
  }
}
