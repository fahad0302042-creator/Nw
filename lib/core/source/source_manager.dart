import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../models/extension_manifest.dart';
import '../storage/app_storage.dart';

/// Keeps the in-memory list of installed [ExtensionManifest]s in sync with
/// [AppStorage], and seeds the app with a few bundled demo/example sources
/// on first launch so there's always something to try immediately.
class SourceManager extends ChangeNotifier {
  SourceManager(this._storage);

  final AppStorage _storage;

  List<ExtensionManifest> _installed = [];
  List<ExtensionManifest> get installed => List.unmodifiable(_installed);

  List<ExtensionManifest> get mangaSources =>
      _installed.where((e) => e.isManga).toList();
  List<ExtensionManifest> get animeSources =>
      _installed.where((e) => e.isAnime).toList();

  ExtensionManifest? byId(String id) {
    for (final e in _installed) {
      if (e.id == id) return e;
    }
    return null;
  }

  Future<void> loadInstalled() async {
    final manifests = await _storage.allInstalledManifests();
    _installed = manifests.map(ExtensionManifest.fromJson).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    notifyListeners();
  }

  Future<void> installFromJson(Map<String, dynamic> json) async {
    // Throws if the manifest is missing required fields.
    ExtensionManifest.fromJson(json);
    await _storage.installExtension(json);
    await loadInstalled();
  }

  Future<void> uninstall(String id) async {
    await _storage.uninstallExtension(id);
    await loadInstalled();
  }

  bool isInstalled(String id) => _installed.any((e) => e.id == id);

  /// Installs the JSON manifests bundled under `assets/extensions/` the
  /// first time the app runs (i.e. when nothing is installed yet and no
  /// repositories have been added), so the Browse tab is never empty.
  Future<void> seedBundledExtensionsIfFirstRun() async {
    if (_storage.installedExtensionIds.isNotEmpty || _storage.repos.isNotEmpty) {
      return;
    }
    try {
      final manifestJson = await rootBundle.loadString('AssetManifest.json');
      final manifest = jsonDecode(manifestJson) as Map<String, dynamic>;
      final assetPaths = manifest.keys
          .where((k) => k.startsWith('assets/extensions/') && k.endsWith('.json'))
          .toList();
      for (final path in assetPaths) {
        final content = await rootBundle.loadString(path);
        final json = jsonDecode(content) as Map<String, dynamic>;
        await _storage.installExtension(json);
      }
    } catch (e) {
      debugPrint('Failed to seed bundled extensions: $e');
    }
    await loadInstalled();
  }
}
