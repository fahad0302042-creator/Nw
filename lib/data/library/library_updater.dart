import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/models/media.dart';
import '../../domain/source/media_source.dart';
import '../db/app_database.dart';
import '../net/app_http_client.dart';
import '../notify/notification_service.dart';

/// Checks library titles for new chapters/episodes.
///
/// Runs sequentially with a small delay between titles. A library of 200
/// series hitting one source in parallel is indistinguishable from an
/// attack, and the resulting ban hurts the user, not us.
class LibraryUpdater extends ChangeNotifier {
  LibraryUpdater({required this.db, required this.resolveSource});

  final AppDatabase db;
  final MediaSource? Function(String sourceId) resolveSource;

  bool _running = false;
  int _done = 0;
  int _total = 0;
  String? _current;
  UpdateResult? _lastResult;
  bool _cancelled = false;

  bool get isRunning => _running;
  int get done => _done;
  int get total => _total;
  String? get currentTitle => _current;
  UpdateResult? get lastResult => _lastResult;

  double? get progress => _total == 0 ? null : _done / _total;

  void cancel() => _cancelled = true;

  /// Checks every library title of [types], or all media if null.
  Future<UpdateResult> run({
    List<MediaType>? types,
    bool notify = true,
    Duration delayBetween = const Duration(milliseconds: 350),
  }) async {
    if (_running) return _lastResult ?? const UpdateResult.empty();

    _running = true;
    _cancelled = false;
    _done = 0;
    _current = null;

    // Background work must never pop a Cloudflare WebView in the user's
    // face; challenged titles are simply skipped until opened manually.
    final wasInteractive = AppHttpClient.interactive;
    AppHttpClient.interactive = false;

    final updated = <String, int>{};
    final failures = <String>[];

    try {
      final items = <MediaItem>[];
      for (final type in types ?? MediaType.values) {
        items.addAll(await db.library(type));
      }
      _total = items.length;
      notifyListeners();

      for (final item in items) {
        if (_cancelled) break;
        _current = item.title;
        notifyListeners();

        final source = resolveSource(item.sourceId);
        final id = item.id;
        if (source == null || id == null) {
          _done++;
          continue;
        }

        try {
          final fresh = await source.units(item);
          final newCount = await db.syncUnits(id, fresh);
          await db.markChecked(id, newCount);
          if (newCount > 0) updated[item.title] = newCount;
        } catch (e) {
          failures.add(item.title);
        }

        _done++;
        notifyListeners();
        if (delayBetween > Duration.zero) await Future.delayed(delayBetween);
      }
    } finally {
      AppHttpClient.interactive = wasInteractive;
      _running = false;
      _current = null;
      notifyListeners();
    }

    final result = UpdateResult(
      titlesWithUpdates: updated.length,
      newUnits: updated.values.fold(0, (a, b) => a + b),
      updatedTitles: updated.keys.toList(),
      failures: failures,
      cancelled: _cancelled,
    );
    _lastResult = result;
    notifyListeners();

    if (notify && result.newUnits > 0) {
      await NotificationService.instance.showLibraryUpdate(
        titles: result.titlesWithUpdates,
        newUnits: result.newUnits,
        sampleTitles: result.updatedTitles,
      );
    }

    return result;
  }
}

class UpdateResult {
  const UpdateResult({
    required this.titlesWithUpdates,
    required this.newUnits,
    required this.updatedTitles,
    required this.failures,
    this.cancelled = false,
  });

  const UpdateResult.empty()
      : titlesWithUpdates = 0,
        newUnits = 0,
        updatedTitles = const [],
        failures = const [],
        cancelled = false;

  final int titlesWithUpdates;
  final int newUnits;
  final List<String> updatedTitles;
  final List<String> failures;
  final bool cancelled;

  String get summary {
    if (cancelled) return 'Update cancelled';
    if (newUnits == 0) {
      return failures.isEmpty
          ? 'No new chapters'
          : 'No new chapters · ${failures.length} failed';
    }
    return '$newUnits new in $titlesWithUpdates '
        '${titlesWithUpdates == 1 ? 'title' : 'titles'}'
        '${failures.isEmpty ? '' : ' · ${failures.length} failed'}';
  }
}
