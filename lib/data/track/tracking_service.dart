import 'package:flutter/foundation.dart';

import '../../domain/models/media.dart';
import '../../domain/models/track.dart';
import '../db/app_database.dart';
import 'anilist_tracker.dart';
import 'mal_tracker.dart';
import 'token_store.dart';
import 'tracker.dart';

/// Owns the tracker instances and the local link records.
///
/// The important behaviour lives in [syncProgress]: progress is only ever
/// pushed *forwards*. Re-reading an old chapter must never tell AniList you
/// have regressed, which is the bug every tracker integration ships first.
class TrackingService extends ChangeNotifier {
  TrackingService({required this.db, required TokenStore tokens})
      : _tokens = tokens,
        trackers = [
          AniListTracker(tokens),
          MalTracker(tokens),
        ];

  final AppDatabase db;
  final TokenStore _tokens;
  final List<Tracker> trackers;

  TokenStore get tokens => _tokens;

  Tracker byId(TrackerId id) => trackers.firstWhere((t) => t.id == id);

  List<Tracker> get loggedIn => trackers.where((t) => t.isLoggedIn).toList();

  bool get anyLoggedIn => loggedIn.isNotEmpty;

  Future<List<TrackLink>> linksFor(int itemId) => db.trackLinks(itemId);

  Future<void> link(int itemId, TrackLink link) async {
    await db.upsertTrackLink(link.copyWith(itemId: itemId));
    notifyListeners();
  }

  Future<void> unlink(TrackLink link) async {
    if (link.id != null) await db.deleteTrackLink(link.id!);
    notifyListeners();
  }

  Future<void> setClientId(TrackerId id, String value) async {
    await _tokens.setClientId(id, value);
    notifyListeners();
  }

  Future<void> logout(TrackerId id) async {
    await byId(id).logout();
    notifyListeners();
  }

  /// Pushes a newly read chapter/episode number to every linked service.
  ///
  /// Silently does nothing when the number is unknown (-1) or not ahead of
  /// what the service already has.
  Future<void> syncProgress({
    required int itemId,
    required MediaType type,
    required double unitNumber,
  }) async {
    if (unitNumber < 0) return;
    final progress = unitNumber.floor();
    if (progress <= 0) return;

    for (final link in await db.trackLinks(itemId)) {
      if (progress <= link.lastProgress) continue;

      final tracker = byId(link.tracker);
      if (!tracker.isLoggedIn) continue;

      // Reaching the final chapter completes the entry, which is what
      // people expect and otherwise have to do by hand.
      final finished = link.totalUnits > 0 && progress >= link.totalUnits;
      final updated = link.copyWith(
        lastProgress: progress,
        status: finished ? TrackStatus.completed : link.status,
      );

      try {
        await tracker.push(updated, type);
        await db.upsertTrackLink(updated);
      } catch (e) {
        // A tracking failure must never interrupt reading.
        debugPrint('Tracker ${link.tracker.name} sync failed: $e');
      }
    }
    notifyListeners();
  }

  /// Pulls the remote state for every link on an item.
  Future<void> refresh(int itemId, MediaType type) async {
    for (final link in await db.trackLinks(itemId)) {
      final tracker = byId(link.tracker);
      if (!tracker.isLoggedIn) continue;
      try {
        final remote = await tracker.fetch(link.remoteId, type);
        if (remote != null) {
          await db.upsertTrackLink(remote.copyWith(id: link.id, itemId: itemId));
        }
      } catch (_) {/* leave the cached record alone */}
    }
    notifyListeners();
  }
}
