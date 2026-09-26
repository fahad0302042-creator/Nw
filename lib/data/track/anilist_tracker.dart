import 'dart:convert';

import 'package:dio/dio.dart';

import '../../domain/models/media.dart';
import '../../domain/models/track.dart';
import 'token_store.dart';
import 'tracker.dart';

/// AniList, via its GraphQL API.
///
/// Uses the implicit grant: AniList hands back the token in the redirect
/// fragment, so no client secret is needed — which matters for an
/// open-source client that cannot keep one secret.
class AniListTracker implements Tracker {
  AniListTracker(this._tokens, {Dio? dio})
      : _dio = dio ?? Dio(BaseOptions(receiveTimeout: const Duration(seconds: 20)));

  final TokenStore _tokens;
  final Dio _dio;

  static const _endpoint = 'https://graphql.anilist.co';

  @override
  TrackerId get id => TrackerId.anilist;

  @override
  String get name => id.label;

  @override
  bool get isLoggedIn => _tokens.accessToken(id) != null;

  @override
  String? get accountName => _tokens.accountName(id);

  String? get clientId => _tokens.clientId(id);

  @override
  Uri authorizationUrl() {
    final client = clientId;
    if (client == null || client.isEmpty) {
      throw TrackerAuthException(id, 'Set your AniList client ID first');
    }
    return Uri.parse(
      'https://anilist.co/api/v2/oauth/authorize'
      '?client_id=$client&response_type=token',
    );
  }

  @override
  Future<bool> handleRedirect(Uri redirect) async {
    // Implicit grant returns `#access_token=...&expires_in=...`
    final fragment = redirect.fragment;
    if (fragment.isEmpty) return false;
    final params = Uri.splitQueryString(fragment);
    final token = params['access_token'];
    if (token == null || token.isEmpty) return false;

    final expires = int.tryParse(params['expires_in'] ?? '');
    await _tokens.saveTokens(
      id,
      access: token,
      expiresIn: expires == null ? null : Duration(seconds: expires),
    );

    // Resolve the account name so settings can show who is signed in.
    try {
      final me = await _query(r'query { Viewer { id name } }', {});
      final name = me?['Viewer']?['name'];
      if (name != null) {
        await _tokens.saveTokens(id, access: token, account: '$name');
      }
    } catch (_) {/* the token still works without a display name */}

    return true;
  }

  @override
  Future<void> logout() => _tokens.clear(id);

  @override
  bool supports(MediaType type) => true;

  String _mediaType(MediaType type) =>
      type == MediaType.manga ? 'MANGA' : 'ANIME';

  Future<Map<String, dynamic>?> _query(
    String query,
    Map<String, dynamic> variables, {
    bool requireAuth = true,
  }) async {
    final token = _tokens.accessToken(id);
    if (requireAuth && token == null) {
      throw TrackerAuthException(id, 'Not signed in');
    }

    final res = await _dio.post<String>(
      _endpoint,
      data: jsonEncode({'query': query, 'variables': variables}),
      options: Options(
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        validateStatus: (_) => true,
        responseType: ResponseType.plain,
      ),
    );

    if (res.statusCode == 401 || res.statusCode == 400 && token != null) {
      final body = res.data ?? '';
      if (body.contains('Invalid token') || res.statusCode == 401) {
        await logout();
        throw TrackerAuthException(id, 'Session expired — sign in again');
      }
    }

    final decoded = jsonDecode(res.data ?? '{}') as Map<String, dynamic>;
    if (decoded['errors'] != null) {
      final first = (decoded['errors'] as List).first;
      throw TrackerAuthException(id, '${first['message']}');
    }
    return decoded['data'] as Map<String, dynamic>?;
  }

  @override
  Future<List<TrackSearchResult>> search(String query, MediaType type) async {
    const gql = r'''
      query ($search: String, $type: MediaType) {
        Page(perPage: 25) {
          media(search: $search, type: $type) {
            id
            title { romaji english }
            coverImage { large }
            chapters
            episodes
            description(asHtml: false)
            siteUrl
          }
        }
      }
    ''';

    final data = await _query(
      gql,
      {'search': query, 'type': _mediaType(type)},
      requireAuth: false,
    );

    final media = (data?['Page']?['media'] as List? ?? const []);
    return media.map((raw) {
      final m = (raw as Map).cast<String, dynamic>();
      final titles = (m['title'] as Map?)?.cast<String, dynamic>() ?? {};
      return TrackSearchResult(
        remoteId: '${m['id']}',
        title: '${titles['english'] ?? titles['romaji'] ?? 'Unknown'}',
        coverUrl: (m['coverImage'] as Map?)?['large'] as String?,
        totalUnits:
            ((type == MediaType.manga ? m['chapters'] : m['episodes']) as int?) ??
                0,
        summary: (m['description'] as String?)
            ?.replaceAll(RegExp(r'<[^>]*>'), '')
            .trim(),
        remoteUrl: m['siteUrl'] as String?,
      );
    }).toList();
  }

  @override
  Future<TrackLink?> fetch(String remoteId, MediaType type) async {
    const gql = r'''
      query ($id: Int) {
        Media(id: $id) {
          id
          title { romaji english }
          coverImage { large }
          chapters
          episodes
          siteUrl
          mediaListEntry { status progress score(format: POINT_10) }
        }
      }
    ''';

    final data = await _query(gql, {'id': int.tryParse(remoteId)});
    final m = (data?['Media'] as Map?)?.cast<String, dynamic>();
    if (m == null) return null;

    final titles = (m['title'] as Map?)?.cast<String, dynamic>() ?? {};
    final entry = (m['mediaListEntry'] as Map?)?.cast<String, dynamic>();

    return TrackLink(
      tracker: id,
      remoteId: '${m['id']}',
      title: '${titles['english'] ?? titles['romaji'] ?? 'Unknown'}',
      status: _fromRemoteStatus(entry?['status'] as String?),
      lastProgress: (entry?['progress'] as int?) ?? 0,
      totalUnits:
          ((type == MediaType.manga ? m['chapters'] : m['episodes']) as int?) ??
              0,
      score: ((entry?['score'] as num?) ?? 0).toDouble(),
      remoteUrl: m['siteUrl'] as String?,
      coverUrl: (m['coverImage'] as Map?)?['large'] as String?,
    );
  }

  @override
  Future<void> push(TrackLink link, MediaType type) async {
    const gql = r'''
      mutation ($mediaId: Int, $status: MediaListStatus, $progress: Int, $score: Float) {
        SaveMediaListEntry(mediaId: $mediaId, status: $status, progress: $progress, score: $score) {
          id
        }
      }
    ''';

    await _query(gql, {
      'mediaId': int.tryParse(link.remoteId),
      'status': _toRemoteStatus(link.status),
      'progress': link.lastProgress,
      'score': link.score,
    });
  }

  static TrackStatus _fromRemoteStatus(String? s) => switch (s) {
        'CURRENT' => TrackStatus.reading,
        'PLANNING' => TrackStatus.planToRead,
        'COMPLETED' => TrackStatus.completed,
        'PAUSED' => TrackStatus.onHold,
        'DROPPED' => TrackStatus.dropped,
        'REPEATING' => TrackStatus.rereading,
        _ => TrackStatus.reading,
      };

  static String _toRemoteStatus(TrackStatus s) => switch (s) {
        TrackStatus.reading => 'CURRENT',
        TrackStatus.planToRead => 'PLANNING',
        TrackStatus.completed => 'COMPLETED',
        TrackStatus.onHold => 'PAUSED',
        TrackStatus.dropped => 'DROPPED',
        TrackStatus.rereading => 'REPEATING',
      };
}
