import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../extensions/manifest.dart';
import '../extensions/repo_service.dart';
import '../models/media.dart';

const String _kRepos = 'repos';
const String _kSources = 'installed_sources';
const String _kLibrary = 'library';
const String _kProgress = 'progress';
const String _kSettings = 'settings';

/// Single app-wide store. Persisted with SharedPreferences as json blobs.
class AppState extends ChangeNotifier {
  AppState({RepoService repoService = const RepoService()})
      : _repoService = repoService;

  final RepoService _repoService;
  late SharedPreferences _prefs;

  List<RepoInfo> repos = <RepoInfo>[];
  List<SourceManifest> installed = <SourceManifest>[];
  List<MediaItem> library = <MediaItem>[];

  /// Cached catalogue per repository url (not persisted).
  final Map<String, List<SourceManifest>> catalogue =
      <String, List<SourceManifest>>{};

  Map<String, dynamic> _progress = <String, dynamic>{};
  Map<String, dynamic> _settings = <String, dynamic>{};

  bool ready = false;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    repos = _readList(_kRepos)
        .map((e) => RepoInfo.fromJson(e))
        .where((e) => e.url.isNotEmpty)
        .toList();
    installed = _readList(_kSources)
        .map((e) => SourceManifest.fromJson(e))
        .toList();
    library = _readList(_kLibrary).map((e) => MediaItem.fromJson(e)).toList();
    _progress = _readMap(_kProgress);
    _settings = _readMap(_kSettings);
    ready = true;
    notifyListeners();
  }

  // ------------------------------------------------------------------ repos

  Future<RepoResult> previewRepo(String url) => _repoService.load(url);

  Future<RepoResult> addRepo(String url) async {
    final result = await _repoService.load(url);
    repos.removeWhere((repo) => repo.url == result.info.url);
    repos.add(result.info);
    catalogue[result.info.url] = result.sources;
    await _persistRepos();
    notifyListeners();
    return result;
  }

  Future<void> removeRepo(String url) async {
    repos.removeWhere((repo) => repo.url == url);
    catalogue.remove(url);
    await _persistRepos();
    notifyListeners();
  }

  Future<List<SourceManifest>> refreshRepo(String url) async {
    final result = await _repoService.load(url);
    catalogue[url] = result.sources;
    final index = repos.indexWhere((repo) => repo.url == url);
    if (index >= 0) repos[index] = result.info;
    await _persistRepos();
    notifyListeners();
    return result.sources;
  }

  Future<void> _persistRepos() => _writeList(
        _kRepos,
        repos.map((repo) => repo.toJson()).toList(),
      );

  // ---------------------------------------------------------------- sources

  bool isInstalled(String id) => installed.any((source) => source.id == id);

  SourceManifest? sourceById(String id) {
    for (final source in installed) {
      if (source.id == id) return source;
    }
    return null;
  }

  Future<void> installSource(SourceManifest source) async {
    installed.removeWhere((existing) => existing.id == source.id);
    installed.add(source);
    await _writeList(_kSources, installed.map((e) => e.toJson()).toList());
    notifyListeners();
  }

  Future<void> uninstallSource(String id) async {
    installed.removeWhere((source) => source.id == id);
    await _writeList(_kSources, installed.map((e) => e.toJson()).toList());
    notifyListeners();
  }

  // ---------------------------------------------------------------- library

  bool inLibrary(MediaItem item) =>
      library.any((entry) => entry.key == item.key);

  Future<void> toggleLibrary(MediaItem item) async {
    if (inLibrary(item)) {
      library.removeWhere((entry) => entry.key == item.key);
    } else {
      library.insert(0, item);
    }
    await _writeList(_kLibrary, library.map((e) => e.toJson()).toList());
    notifyListeners();
  }

  // --------------------------------------------------------------- progress

  String _chapterKey(String sourceId, String chapterUrl) =>
      'c:$sourceId|$chapterUrl';

  String _mediaKey(String sourceId, String mediaUrl) => 'm:$sourceId|$mediaUrl';

  int progressFor(String sourceId, String chapterUrl) {
    final value = _progress[_chapterKey(sourceId, chapterUrl)];
    if (value is num) return value.toInt();
    return 0;
  }

  bool isRead(String sourceId, String chapterUrl) =>
      _progress.containsKey(_chapterKey(sourceId, chapterUrl));

  String? lastChapterUrl(String sourceId, String mediaUrl) {
    final value = _progress[_mediaKey(sourceId, mediaUrl)];
    return value is String ? value : null;
  }

  Future<void> saveProgress({
    required String sourceId,
    required String mediaUrl,
    required String chapterUrl,
    required int position,
  }) async {
    _progress[_chapterKey(sourceId, chapterUrl)] = position;
    _progress[_mediaKey(sourceId, mediaUrl)] = chapterUrl;
    await _prefs.setString(_kProgress, json.encode(_progress));
    notifyListeners();
  }

  Future<void> clearProgress() async {
    _progress = <String, dynamic>{};
    await _prefs.setString(_kProgress, json.encode(_progress));
    notifyListeners();
  }

  // --------------------------------------------------------------- settings

  bool get webtoonMode => _settings['webtoon'] as bool? ?? true;
  bool get rightToLeft => _settings['rtl'] as bool? ?? false;
  bool get keepScreenOn => _settings['keepScreenOn'] as bool? ?? true;

  Future<void> setSetting(String key, Object value) async {
    _settings[key] = value;
    await _prefs.setString(_kSettings, json.encode(_settings));
    notifyListeners();
  }

  // ---------------------------------------------------------------- storage

  List<Map<String, dynamic>> _readList(String key) {
    final raw = _prefs.getString(key);
    if (raw == null || raw.isEmpty) return <Map<String, dynamic>>[];
    try {
      final decoded = json.decode(raw);
      if (decoded is! List) return <Map<String, dynamic>>[];
      return decoded
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  Map<String, dynamic> _readMap(String key) {
    final raw = _prefs.getString(key);
    if (raw == null || raw.isEmpty) return <String, dynamic>{};
    try {
      final decoded = json.decode(raw);
      if (decoded is Map) return decoded.cast<String, dynamic>();
    } catch (_) {
      // ignored, fall through to empty map
    }
    return <String, dynamic>{};
  }

  Future<void> _writeList(String key, List<Map<String, dynamic>> value) =>
      _prefs.setString(key, json.encode(value));
}
