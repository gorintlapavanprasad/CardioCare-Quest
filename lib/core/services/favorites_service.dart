// FavoritesService - stores a participant's starred game IDs in Firestore
// so they sync across devices. Was SharedPreferences-only before, which meant
// stars were per-device. Writes work offline via OfflineQueue.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';

import '../constants/firestore_paths.dart';
import 'offline_queue.dart';

// Tracks which games a participant starred, synced across devices.
class FavoritesService {
  FavoritesService._();
  static final FavoritesService instance = FavoritesService._();

  // Currently-loaded participant. null until load() is called.
  String? _participantId;

  // Live Firestore subscription. Cancelled on participant change or clear().
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;

  // In-memory set of starred game ids. Emits a new Set on each update.
  final ValueNotifier<Set<String>> favorites =
      ValueNotifier<Set<String>>(<String>{});

  OfflineQueue get _queue => GetIt.instance<OfflineQueue>();

  // Firestore path for this participant's favorites doc.
  String _docPath(String uid) =>
      '${FirestorePaths.userData}/$uid/${FirestorePaths.preferences}/${FirestorePaths.favorites}';

  // Subscribe to the favorites doc. Safe to call repeatedly; only re-subscribes
  // when the participant changes.
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
      debugPrint('FavoritesService: snapshot error - $e');
    });
  }

  // Is this game currently starred?
  bool isFavorite(String gameId) => favorites.value.contains(gameId);

  // Toggle a game's starred state. Returns the new state.
  // Updates in memory immediately so the UI responds before the cloud write.
  Future<bool> toggle(String gameId) async {
    final pid = _participantId;
    if (pid == null || pid.isEmpty) {
      debugPrint('FavoritesService.toggle: no participant loaded - skipping');
      return favorites.value.contains(gameId);
    }
    final current = Set<String>.from(favorites.value);
    final wasFavorite = current.contains(gameId);
    if (wasFavorite) {
      current.remove(gameId);
    } else {
      current.add(gameId);
    }
    // Update in memory first for an instant UI response.
    favorites.value = current;

    // Overwrite gameIds. Uses set+merge so it creates the doc on first toggle.
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

  // Clear the cache and unsubscribe. Call on logout so the next participant
  // doesn't briefly see the previous user's starred games.
  void clear() {
    _participantId = null;
    _sub?.cancel();
    _sub = null;
    favorites.value = <String>{};
  }
}
