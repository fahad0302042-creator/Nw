import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../models/library_entry.dart';

/// A tiny JSON-file backed persistence layer.
///
/// Tsundoku deliberately avoids a heavier database dependency (Hive/Drift +
/// code generation) to keep the build simple and CI-friendly. Everything is
/// small enough (a library list, install list, and read-progress map) that a
/// single JSON document is plenty fast.
class AppStorage extends ChangeNotifier {
  AppStorage._();

  static final AppStorage instance = AppStorage._();

  Directory? _dir;
  Map<String, dynamic> _db = {
    'repos': <String>[],
    'installedExtensionIds': <String>[],
    'library': <Map<String, dynamic>>[],
    'progress': <String, dynamic>{},
    'settings': <String, dynamic>{},
  };

  bool _ready = false;
  bool get isReady => _ready;

  Future<Directory> _resolveDir() async {
    _dir ??= await getApplicationDocumentsDirectory();
    return _dir!;
  }

  File _dbFile(Directory dir) => File('${dir.path}/tsundoku_db.json');

  Directory _extensionsDir(Directory dir) => Directory('${dir.path}/extensions');

  Future<void> init() async {
    if (_ready) return;
    final dir = await _resolveDir();
    final file = _dbFile(dir);
    if (await file.exists()) {
      try {
        final content = await file.readAsString();
        final decoded = jsonDecode(content) as Map<String, dynamic>;
        _db = {..._db, ...decoded};
      } catch (_) {
        // Corrupt file - start fresh rather than crash the app.
      }
    }
    final extDir = _extensionsDir(dir);
    if (!await extDir.exists()) {
      await extDir.create(recursive: true);
    }
    _ready = true;
    notifyListeners();
  }

  Future<void> _save() async {
    final dir = await _resolveDir();
    final file = _dbFile(dir);
    await file.writeAsString(jsonEncode(_db));
  }

  // ---------------------------------------------------------------------
  // Repositories
  // ---------------------------------------------------------------------

  List<String> get repos => List<String>.from(_db['repos'] as List? ?? []);

  Future<void> addRepo(String url) async {
    final list = repos;
    if (!list.contains(url)) {
      list.add(url);
      _db['repos'] = list;
      await _save();
      notifyListeners();
    }
  }

  Future<void> removeRepo(String url) async {
    final list = repos..remove(url);
    _db['repos'] = list;
    await _save();
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // Installed extensions (manifests cached as individual JSON files)
  // ---------------------------------------------------------------------

  List<String> get installedExtensionIds =>
      List<String>.from(_db['installedExtensionIds'] as List? ?? []);

  Future<File> _extensionFile(String id) async {
    final dir = await _resolveDir();
    return File('${_extensionsDir(dir).path}/$id.json');
  }

  Future<Map<String, dynamic>?> readExtensionManifest(String id) async {
    final file = await _extensionFile(id);
    if (!await file.exists()) return null;
    try {
      return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> installExtension(Map<String, dynamic> manifestJson) async {
    final id = manifestJson['id'] as String;
    final file = await _extensionFile(id);
    await file.writeAsString(jsonEncode(manifestJson));
    final ids = installedExtensionIds;
    if (!ids.contains(id)) {
      ids.add(id);
      _db['installedExtensionIds'] = ids;
      await _save();
    }
    notifyListeners();
  }

  Future<void> uninstallExtension(String id) async {
    final ids = installedExtensionIds..remove(id);
    _db['installedExtensionIds'] = ids;
    await _save();
    final file = await _extensionFile(id);
    if (await file.exists()) await file.delete();
    notifyListeners();
  }

  Future<List<Map<String, dynamic>>> allInstalledManifests() async {
    final result = <Map<String, dynamic>>[];
    for (final id in installedExtensionIds) {
      final manifest = await readExtensionManifest(id);
      if (manifest != null) result.add(manifest);
    }
    return result;
  }

  // ---------------------------------------------------------------------
  // Library
  // ---------------------------------------------------------------------

  List<LibraryEntry> get library => (_db['library'] as List? ?? [])
      .map((e) => LibraryEntry.fromJson(Map<String, dynamic>.from(e as Map)))
      .toList();

  bool isInLibrary(String sourceId, String url) =>
      library.any((e) => e.item.sourceId == sourceId && e.item.url == url);

  Future<void> addToLibrary(LibraryEntry entry) async {
    final list = library;
    if (!list.any(
      (e) => e.item.sourceId == entry.item.sourceId && e.item.url == entry.item.url,
    )) {
      list.add(entry);
      _db['library'] = list.map((e) => e.toJson()).toList();
      await _save();
      notifyListeners();
    }
  }

  Future<void> removeFromLibrary(String sourceId, String url) async {
    final list = library
        .where((e) => !(e.item.sourceId == sourceId && e.item.url == url))
        .toList();
    _db['library'] = list.map((e) => e.toJson()).toList();
    await _save();
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // Reading / watching progress
  // ---------------------------------------------------------------------

  String _progressKey(String sourceId, String mangaUrl) => '$sourceId::$mangaUrl';

  Map<String, dynamic> _progressFor(String sourceId, String mangaUrl) {
    final progress = Map<String, dynamic>.from(_db['progress'] as Map? ?? {});
    final key = _progressKey(sourceId, mangaUrl);
    return Map<String, dynamic>.from(
      progress[key] as Map? ?? {'read': <String>[], 'last': null},
    );
  }

  Set<String> readChapterUrls(String sourceId, String mangaUrl) =>
      Set<String>.from(_progressFor(sourceId, mangaUrl)['read'] as List? ?? []);

  String? lastReadChapterUrl(String sourceId, String mangaUrl) =>
      _progressFor(sourceId, mangaUrl)['last'] as String?;

  Future<void> markChapterRead(
    String sourceId,
    String mangaUrl,
    String chapterUrl,
  ) async {
    final progress = Map<String, dynamic>.from(_db['progress'] as Map? ?? {});
    final key = _progressKey(sourceId, mangaUrl);
    final entry = _progressFor(sourceId, mangaUrl);
    final readSet = Set<String>.from(entry['read'] as List? ?? [])..add(chapterUrl);
    progress[key] = {'read': readSet.toList(), 'last': chapterUrl};
    _db['progress'] = progress;
    await _save();
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // Settings
  // ---------------------------------------------------------------------

  Map<String, dynamic> get settings =>
      Map<String, dynamic>.from(_db['settings'] as Map? ?? {});

  Future<void> setSetting(String key, dynamic value) async {
    final s = settings;
    s[key] = value;
    _db['settings'] = s;
    await _save();
    notifyListeners();
  }
}
