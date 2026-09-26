import 'dart:convert';

import 'package:dio/dio.dart';

import 'extension.dart';

/// A remote catalogue of extensions, addressed by the URL of its
/// `index.json` — the same mental model as adding a Keiyoushi repo in Mihon.
///
/// Expected shape:
/// ```json
/// {
///   "name": "My Repo",
///   "extensions": [
///     { "id": "en.example", "name": "Example", "version": "1.0.0",
///       "lang": "en", "type": "manga", "code": "src/en.example/index.js" }
///   ]
/// }
/// ```
/// Relative `code`/`icon` paths are resolved against the index URL, so a repo
/// can simply be a folder on GitHub Pages or a raw.githubusercontent.com path.
class ExtensionRepository {
  ExtensionRepository({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 20),
              responseType: ResponseType.plain,
            ));

  final Dio _dio;

  Future<RepoIndex> fetchIndex(String indexUrl) async {
    final res = await _dio.get<String>(indexUrl);
    final body = res.data ?? '';
    final decoded = jsonDecode(body);

    final base = Uri.parse(indexUrl);
    String abs(String? u) =>
        (u == null || u.isEmpty) ? '' : base.resolve(u).toString();

    final Map<String, dynamic> map = decoded is List
        ? {'name': base.host, 'extensions': decoded}
        : (decoded as Map).cast<String, dynamic>();

    final exts = (map['extensions'] as List? ?? const [])
        .map((e) {
          final j = (e as Map).cast<String, dynamic>();
          return ExtensionInfo.fromJson({
            ...j,
            'code': abs('${j['code'] ?? j['codeUrl'] ?? ''}'),
            'icon': j['icon'] == null ? null : abs('${j['icon']}'),
          }, repoUrl: indexUrl);
        })
        .where((e) => e.codeUrl.isNotEmpty)
        .toList();

    return RepoIndex(
      url: indexUrl,
      name: '${map['name'] ?? base.host}',
      extensions: exts,
    );
  }

  Future<String> fetchCode(String codeUrl) async {
    final res = await _dio.get<String>(codeUrl);
    final code = res.data ?? '';
    if (code.trim().isEmpty) {
      throw StateError('Extension bundle at $codeUrl is empty');
    }
    return code;
  }
}

class RepoIndex {
  const RepoIndex({
    required this.url,
    required this.name,
    required this.extensions,
  });
  final String url;
  final String name;
  final List<ExtensionInfo> extensions;
}
