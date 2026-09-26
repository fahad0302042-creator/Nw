import 'dart:convert';

import 'package:dio/dio.dart';

import '../../models/extension_manifest.dart';
import '../../models/extension_summary.dart';
import '../network/http_client.dart';

/// Fetches and validates extension repositories / individual extension
/// manifests from arbitrary URLs the user pastes in.
///
/// Two URL shapes are accepted, auto-detected from the JSON shape:
///   1. A **repository index**: `{"name": "...", "extensions": [...]}` -
///      each entry either embeds a full manifest or points at one via
///      `sourceUrl`.
///   2. A **single extension manifest** directly (has `id` + `baseUrl`).
class ExtensionRepository {
  const ExtensionRepository();

  Future<dynamic> _getJson(String url) async {
    final response = await AppHttpClient.dio.get(
      url,
      options: Options(responseType: ResponseType.plain),
    );
    final data = response.data;
    return data is String ? jsonDecode(data) : data;
  }

  /// Returns `true` if [url] looks like it resolves to a repo index vs a
  /// single manifest. Throws on network/parse errors so the caller can show
  /// a useful message.
  Future<RepoFetchResult> fetch(String url) async {
    final json = await _getJson(url);
    if (json is Map && json['extensions'] is List) {
      final list = (json['extensions'] as List)
          .whereType<Map>()
          .map((e) => _summaryFromJson(Map<String, dynamic>.from(e), url))
          .toList();
      return RepoFetchResult.repo(list);
    }
    if (json is Map && json['id'] != null && json['baseUrl'] != null) {
      final manifest = ExtensionManifest.fromJson(Map<String, dynamic>.from(json));
      return RepoFetchResult.singleExtension(manifest);
    }
    throw const FormatException(
      'Unrecognized JSON: expected a repository index ({"extensions": [...]}) '
      'or a single extension manifest ({"id": ..., "baseUrl": ...}).',
    );
  }

  ExtensionSummary _summaryFromJson(Map<String, dynamic> json, String repoUrl) {
    final hasFullManifest = json['baseUrl'] != null;
    return ExtensionSummary(
      id: json['id'] as String,
      name: json['name'] as String? ?? json['id'] as String,
      lang: json['lang'] as String? ?? 'en',
      version: json['version']?.toString() ?? '1.0.0',
      type: json['type'] as String? ?? 'manga',
      icon: json['icon'] as String?,
      description: json['description'] as String?,
      sourceUrl: hasFullManifest ? '' : (json['sourceUrl'] as String? ?? ''),
      inline: hasFullManifest ? json : null,
      repoUrl: repoUrl,
    );
  }

  /// Downloads (if needed) and parses the full manifest for [summary].
  Future<ExtensionManifest> resolveManifest(ExtensionSummary summary) async {
    if (summary.inline != null) {
      return ExtensionManifest.fromJson(summary.inline!);
    }
    final json = await _getJson(summary.sourceUrl);
    return ExtensionManifest.fromJson(Map<String, dynamic>.from(json as Map));
  }
}

class RepoFetchResult {
  final List<ExtensionSummary>? extensions;
  final ExtensionManifest? singleManifest;

  const RepoFetchResult._(this.extensions, this.singleManifest);

  factory RepoFetchResult.repo(List<ExtensionSummary> list) =>
      RepoFetchResult._(list, null);

  factory RepoFetchResult.singleExtension(ExtensionManifest manifest) =>
      RepoFetchResult._(null, manifest);

  bool get isRepo => extensions != null;
}
