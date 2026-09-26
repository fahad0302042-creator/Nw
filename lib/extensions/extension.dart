import '../domain/models/media.dart';
import 'js_source.dart';
import 'js_runtime.dart';

/// Metadata for an extension as published in a repository `index.json`.
class ExtensionInfo {
  const ExtensionInfo({
    required this.id,
    required this.name,
    required this.version,
    required this.lang,
    required this.type,
    required this.codeUrl,
    this.iconUrl,
    this.nsfw = false,
    this.repoUrl = '',
    this.description,
  });

  final String id;
  final String name;
  final String version;
  final String lang;
  final MediaType type;

  /// Absolute URL of the extension's JavaScript bundle.
  final String codeUrl;
  final String? iconUrl;
  final bool nsfw;
  final String repoUrl;
  final String? description;

  factory ExtensionInfo.fromJson(Map<String, dynamic> j, {String repoUrl = ''}) =>
      ExtensionInfo(
        id: '${j['id']}',
        name: '${j['name']}',
        version: '${j['version'] ?? '1.0.0'}',
        lang: '${j['lang'] ?? 'en'}',
        type: MediaTypeX.parse('${j['type']}'),
        codeUrl: '${j['code'] ?? j['codeUrl'] ?? ''}',
        iconUrl: j['icon']?.toString(),
        nsfw: j['nsfw'] == true,
        repoUrl: repoUrl,
        description: j['description']?.toString(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'version': version,
        'lang': lang,
        'type': type.name,
        'code': codeUrl,
        'icon': iconUrl,
        'nsfw': nsfw,
        'repo': repoUrl,
        'description': description,
      };

  /// Naive but predictable semver-ish comparison used for update checks.
  bool isNewerThan(String other) {
    List<int> parts(String v) => v
        .split(RegExp(r'[.\-+]'))
        .map((e) => int.tryParse(e) ?? 0)
        .toList();
    final a = parts(version), b = parts(other);
    for (var i = 0; i < a.length || i < b.length; i++) {
      final x = i < a.length ? a[i] : 0;
      final y = i < b.length ? b[i] : 0;
      if (x != y) return x > y;
    }
    return false;
  }
}

/// An installed, loaded extension and the sources it registered.
class LoadedExtension {
  LoadedExtension({
    required this.info,
    required this.host,
    required this.sources,
  });

  final ExtensionInfo info;
  final JsRuntimeHost host;
  final List<JsSource> sources;

  void dispose() => host.dispose();
}
