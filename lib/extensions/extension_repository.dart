import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'extension.dart';
import 'repo_url.dart';

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
              // Bytes, not plain: the body may be compressed or simply not
              // text, and we want to diagnose that rather than hand
              // mojibake to jsonDecode.
              responseType: ResponseType.bytes,
              validateStatus: (_) => true,
              headers: const {
                'Accept': 'application/json, text/plain, */*',
                // Deliberately no `br`: dart:io cannot decode brotli, and a
                // CDN that honours it hands back bytes we cannot read.
                'Accept-Encoding': 'gzip, deflate',
              },
            ));

  final Dio _dio;

  Future<RepoIndex> fetchIndex(String rawUrl) async {
    final indexUrl = RepoUrl.normalize(rawUrl);
    final body = await _fetchText(indexUrl, what: 'repository index');

    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException catch (e) {
      throw RepoException(_describeNonJson(body, indexUrl, e));
    }

    final base = Uri.parse(indexUrl);
    String abs(String? u) =>
        (u == null || u.isEmpty) ? '' : base.resolve(u).toString();

    if (decoded is! Map && decoded is! List) {
      throw RepoException(
        'That URL returned JSON, but not a repository index — expected an '
        'object with an "extensions" list.',
      );
    }

    final Map<String, dynamic> map = decoded is List
        ? {'name': base.host, 'extensions': decoded}
        : (decoded as Map).cast<String, dynamic>();

    if (map['extensions'] is! List) {
      throw RepoException(
        'This JSON has no "extensions" list, so it is not a Kurayomi '
        'repository index.',
      );
    }

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
    final code = await _fetchText(codeUrl, what: 'extension bundle');
    if (code.trim().isEmpty) {
      throw RepoException('Extension bundle at $codeUrl is empty');
    }
    return code;
  }

  // ------------------------------------------------------------- internals

  Future<String> _fetchText(String url, {required String what}) async {
    final Response<List<int>> res;
    try {
      res = await _dio.get<List<int>>(url);
    } on DioException catch (e) {
      throw RepoException(
        'Could not reach $url\n\n${e.message ?? e.type.name}',
      );
    }

    final status = res.statusCode ?? 0;
    if (status >= 400) {
      throw RepoException(
        status == 404
            ? 'Nothing found at $url (404).\n\nCheck the URL points directly '
                'at the index.json file.'
            : 'Server returned HTTP $status for $url',
      );
    }

    final bytes = Uint8List.fromList(res.data ?? const []);
    if (bytes.isEmpty) throw RepoException('The $what at $url was empty');

    return decodeBody(bytes);
  }

  /// Turns a response body into text, undoing compression the HTTP stack
  /// did not.
  ///
  /// Exposed for testing: getting this wrong is exactly what produced a
  /// screenful of mojibake instead of an error message.
  static String decodeBody(Uint8List bytes) {
    var data = bytes;

    // gzip — some servers set no Content-Encoding, so dart:io never
    // unwraps it, and a few double-encode.
    var guard = 0;
    while (data.length > 2 &&
        data[0] == 0x1f &&
        data[1] == 0x8b &&
        guard++ < 3) {
      try {
        data = Uint8List.fromList(gzip.decode(data));
      } catch (_) {
        break;
      }
    }

    // raw zlib/deflate
    if (data.length > 2 &&
        data[0] == 0x78 &&
        const [0x01, 0x5e, 0x9c, 0xda].contains(data[1])) {
      try {
        data = Uint8List.fromList(zlib.decode(data));
      } catch (_) {/* not actually zlib */}
    }

    // Strip a UTF-8 BOM, which jsonDecode rejects as an unexpected character.
    if (data.length >= 3 &&
        data[0] == 0xEF &&
        data[1] == 0xBB &&
        data[2] == 0xBF) {
      data = Uint8List.sublistView(data, 3);
    }

    return utf8.decode(data, allowMalformed: true);
  }

  /// Builds an explanation a person can act on, instead of echoing bytes.
  static String _describeNonJson(
      String body, String url, FormatException error) {
    final head = body.trimLeft();
    final preview = head.length > 120 ? '${head.substring(0, 120)}…' : head;

    if (head.startsWith('<')) {
      final isGithub = url.contains('github.com');
      return 'That URL returned a web page, not JSON.'
          '${isGithub ? '\n\nOn GitHub, open the index.json file and use the '
              '"Raw" button — the page URL will not work.' : ''}'
          '\n\nURL: $url';
    }

    if (head.startsWith('PK')) {
      return 'That URL is a ZIP or APK file.\n\nKurayomi extensions are '
          'JavaScript, not Android packages — Keiyoushi/Aniyomi .apk '
          'extensions cannot be loaded. Point this at an index.json instead.';
    }

    // Unprintable bytes: almost always still-compressed or plain binary.
    final unprintable = head.runes
        .take(40)
        .where((r) => r < 9 || (r > 13 && r < 32) || r == 0xFFFD)
        .length;
    if (unprintable > 4) {
      return 'That URL returned binary data, not JSON.\n\nIt may be a '
          'compressed or non-text file. Check the link opens as plain JSON '
          'in a browser.\n\nURL: $url';
    }

    return 'That URL did not return valid JSON.\n\n'
        '${error.message}\n\nStarts with: $preview';
  }
}

/// A repository problem worth showing verbatim to the user.
class RepoException implements Exception {
  RepoException(this.message);
  final String message;
  @override
  String toString() => message;
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
