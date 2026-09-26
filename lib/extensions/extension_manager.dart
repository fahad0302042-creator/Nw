import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/source/media_source.dart';
import 'extension.dart';
import 'extension_repository.dart';
import 'js_runtime.dart';
import 'js_source.dart';

/// Installs, loads, updates and removes extensions.
///
/// Installed bundles live on disk under `<appSupport>/extensions/<id>.js`
/// with their metadata mirrored in SharedPreferences, so startup is offline
/// and instant — no repo round-trip needed to use what you already have.
class ExtensionManager extends ChangeNotifier {
  ExtensionManager({ExtensionRepository? repository})
      : _repo = repository ?? ExtensionRepository();

  final ExtensionRepository _repo;

  static const _kInstalledKey = 'installed_extensions';
  static const _kReposKey = 'extension_repos';

  final Map<String, LoadedExtension> _loaded = {};
  final Map<String, ExtensionInfo> _installed = {};
  final List<String> _repoUrls = [];
  final Map<String, ExtensionInfo> _available = {};

  bool _initialised = false;
  String? lastError;

  List<ExtensionInfo> get installed => _installed.values.toList()
    ..sort((a, b) => a.name.compareTo(b.name));

  List<String> get repoUrls => List.unmodifiable(_repoUrls);

  /// Extensions seen in repos that are not installed yet.
  List<ExtensionInfo> get available => _available.values
      .where((e) => !_installed.containsKey(e.id))
      .toList()
    ..sort((a, b) => a.name.compareTo(b.name));

  /// Installed extensions for which a repo advertises a newer version.
  List<ExtensionInfo> get updates => _available.values
      .where((e) =>
          _installed.containsKey(e.id) &&
          e.isNewerThan(_installed[e.id]!.version))
      .toList();

  List<MediaSource> get sources =>
      _loaded.values.expand((e) => e.sources).toList();

  MediaSource? sourceById(String id) {
    for (final ext in _loaded.values) {
      for (final s in ext.sources) {
        if (s.id == id) return s;
      }
    }
    return null;
  }

  // --------------------------------------------------------------- lifecycle

  Future<void> init() async {
    if (_initialised) return;
    _initialised = true;

    final prefs = await SharedPreferences.getInstance();
    _repoUrls
      ..clear()
      ..addAll(prefs.getStringList(_kReposKey) ?? const []);

    for (final raw in prefs.getStringList(_kInstalledKey) ?? const <String>[]) {
      try {
        final info =
            ExtensionInfo.fromJson((jsonDecode(raw) as Map).cast<String, dynamic>());
        _installed[info.id] = info;
      } catch (_) {}
    }

    for (final info in _installed.values.toList()) {
      try {
        await _load(info);
      } catch (e) {
        lastError = 'Failed to load ${info.name}: $e';
      }
    }
    notifyListeners();

    // Refresh catalogues in the background: installed extensions already
    // work offline, so this must never block first paint.
    if (_repoUrls.isNotEmpty) unawaited(refreshRepos());
  }

  Future<Directory> _dir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'extensions'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  Future<File> _file(String id) async =>
      File(p.join((await _dir()).path, '$id.js'));

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _kInstalledKey,
      _installed.values.map((e) => jsonEncode(e.toJson())).toList(),
    );
    await prefs.setStringList(_kReposKey, _repoUrls);
  }

  // ------------------------------------------------------------------ repos

  Future<void> addRepo(String indexUrl) async {
    final url = indexUrl.trim();
    if (url.isEmpty || _repoUrls.contains(url)) return;
    // Validate before persisting so a typo doesn't stick around.
    final index = await _repo.fetchIndex(url);
    _repoUrls.add(url);
    for (final e in index.extensions) {
      _available[e.id] = e;
    }
    await _persist();
    notifyListeners();
  }

  Future<void> removeRepo(String indexUrl) async {
    _repoUrls.remove(indexUrl);
    _available.removeWhere((_, v) => v.repoUrl == indexUrl);
    await _persist();
    notifyListeners();
  }

  /// Re-reads every configured repo. Failures are collected, not fatal —
  /// one dead repo must not hide the others.
  Future<void> refreshRepos() async {
    final errors = <String>[];
    for (final url in _repoUrls) {
      try {
        final index = await _repo.fetchIndex(url);
        _available.removeWhere((_, v) => v.repoUrl == url);
        for (final e in index.extensions) {
          _available[e.id] = e;
        }
      } catch (e) {
        errors.add('$url: $e');
      }
    }
    lastError = errors.isEmpty ? null : errors.join('\n');
    notifyListeners();
  }

  // --------------------------------------------------------------- install

  Future<void> install(ExtensionInfo info) async {
    final code = await _repo.fetchCode(info.codeUrl);
    await (await _file(info.id)).writeAsString(code);
    _installed[info.id] = info;
    await _persist();
    await _reload(info);
    notifyListeners();
  }

  /// Installs an extension from a raw JS bundle the user supplied directly
  /// (file picker, clipboard, or a local dev server) — invaluable while
  /// writing your own extension.
  Future<void> installFromCode(ExtensionInfo info, String code) async {
    await (await _file(info.id)).writeAsString(code);
    _installed[info.id] = info;
    await _persist();
    await _reload(info);
    notifyListeners();
  }

  Future<void> update(ExtensionInfo newer) => install(newer);

  Future<void> uninstall(String id) async {
    _loaded.remove(id)?.dispose();
    _installed.remove(id);
    final f = await _file(id);
    if (f.existsSync()) f.deleteSync();
    await _persist();
    notifyListeners();
  }

  Future<void> _reload(ExtensionInfo info) async {
    _loaded.remove(info.id)?.dispose();
    await _load(info);
  }

  Future<void> _load(ExtensionInfo info) async {
    final file = await _file(info.id);
    if (!file.existsSync()) {
      throw StateError('Bundle for ${info.id} is missing on disk');
    }
    final host = JsRuntimeHost(
      extensionId: info.id,
      store: _PrefsStore(),
    );
    await host.init(await file.readAsString());

    final manifests = await host.readSourceManifests();
    if (manifests.isEmpty) {
      host.dispose();
      throw StateError('${info.name} registered no sources');
    }

    final sources = <JsSource>[];
    for (final m in manifests) {
      final s = JsSource.fromManifest(m, host: host, extensionId: info.id);
      if (m['hasFilters'] == true) await s.loadFilters();
      sources.add(s);
    }

    _loaded[info.id] = LoadedExtension(
      info: info,
      host: host,
      sources: sources,
    );
  }

  @override
  void dispose() {
    for (final e in _loaded.values) {
      e.dispose();
    }
    _loaded.clear();
    super.dispose();
  }
}

class _PrefsStore implements ExtensionStore {
  @override
  Future<String?> get(String key) async =>
      (await SharedPreferences.getInstance()).getString('ext_store:$key');

  @override
  Future<void> set(String key, String? value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value == null) {
      await prefs.remove('ext_store:$key');
    } else {
      await prefs.setString('ext_store:$key', value);
    }
  }
}
