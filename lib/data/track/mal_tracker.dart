import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';

import '../../domain/models/media.dart';
import '../../domain/models/track.dart';
import 'token_store.dart';
import 'tracker.dart';

/// MyAnimeList, via the official v2 REST API.
///
/// MAL requires OAuth2 with PKCE. Note their quirk: they only accept the
/// `plain` code challenge method, so the verifier is sent as-is. We still
/// generate a high-entropy verifier, which is what actually protects the
/// exchange for a public client.
class MalTracker implements Tracker {
  MalTracker(this._tokens, {Dio? dio})
      : _dio = dio ?? Dio(BaseOptions(receiveTimeout: const Duration(seconds: 20)));

  final TokenStore _tokens;
  final Dio _dio;

  static const _api = 'https://api.myanimelist.net/v2';
  static const _redirect = 'kurayomi://mal-auth';

  @override
  TrackerId get id => TrackerId.myanimelist;

  @override
  String get name => id.label;

  @override
  bool get isLoggedIn => _tokens.accessToken(id) != null;

  @override
  String? get accountName => _tokens.accountName(id);

  String? get clientId => _tokens.clientId(id);

  @override
  bool supports(MediaType type) => true;

  static String _randomVerifier() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(64, (_) => rnd.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '').substring(0, 128);
  }

  @override
  Uri authorizationUrl() {
    final client = clientId;
    if (client == null || client.isEmpty) {
      throw TrackerAuthException(id, 'Set your MyAnimeList client ID first');
    }
    final verifier = _randomVerifier();
    // Fire-and-forget: the redirect cannot arrive before this completes.
    _tokens.setPkceVerifier(id, verifier);

    return Uri.parse('https://myanimelist.net/v1/oauth2/authorize').replace(
      queryParameters: {
        'response_type': 'code',
        'client_id': client,
        'code_challenge': verifier,
        'code_challenge_method': 'plain',
        'redirect_uri': _redirect,
      },
    );
  }

  @override
  Future<bool> handleRedirect(Uri redirect) async {
    final code = redirect.queryParameters['code'];
    if (code == null || code.isEmpty) return false;

    final verifier = _tokens.pkceVerifier(id);
    final client = clientId;
    if (verifier == null || client == null) return false;

    final res = await _dio.post<String>(
      'https://myanimelist.net/v1/oauth2/token',
      data: {
        'client_id': client,
        'grant_type': 'authorization_code',
        'code': code,
        'code_verifier': verifier,
        'redirect_uri': _redirect,
      },
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        validateStatus: (_) => true,
        responseType: ResponseType.plain,
      ),
    );

    if ((res.statusCode ?? 0) >= 400) {
      throw TrackerAuthException(id, 'Token exchange failed: ${res.data}');
    }

    final body = jsonDecode(res.data ?? '{}') as Map<String, dynamic>;
    final access = body['access_token'] as String?;
    if (access == null) return false;

    await _tokens.saveTokens(
      id,
      access: access,
      refresh: body['refresh_token'] as String?,
      expiresIn: Duration(seconds: (body['expires_in'] as num?)?.toInt() ?? 0),
    );

    try {
      final me = await _get('/users/@me', {});
      if (me?['name'] != null) {
        await _tokens.saveTokens(id, access: access, account: '${me!['name']}');
      }
    } catch (_) {}

    return true;
  }

  /// MAL access tokens last ~31 days; refresh silently when possible so the
  /// user is not thrown back to a login screen mid-session.
  Future<void> _refreshIfNeeded() async {
    if (!_tokens.isExpired(id)) return;
    final refresh = _tokens.refreshToken(id);
    final client = clientId;
    if (refresh == null || client == null) return;

    final res = await _dio.post<String>(
      'https://myanimelist.net/v1/oauth2/token',
      data: {
        'client_id': client,
        'grant_type': 'refresh_token',
        'refresh_token': refresh,
      },
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        validateStatus: (_) => true,
        responseType: ResponseType.plain,
      ),
    );
    if ((res.statusCode ?? 0) >= 400) return;

    final body = jsonDecode(res.data ?? '{}') as Map<String, dynamic>;
    final access = body['access_token'] as String?;
    if (access == null) return;
    await _tokens.saveTokens(
      id,
      access: access,
      refresh: body['refresh_token'] as String?,
      expiresIn: Duration(seconds: (body['expires_in'] as num?)?.toInt() ?? 0),
    );
  }

  @override
  Future<void> logout() => _tokens.clear(id);

  Future<Map<String, dynamic>?> _get(
      String path, Map<String, dynamic> query) async {
    await _refreshIfNeeded();
    final token = _tokens.accessToken(id);
    if (token == null) throw TrackerAuthException(id, 'Not signed in');

    final res = await _dio.get<String>(
      '$_api$path',
      queryParameters: query,
      options: Options(
        headers: {'Authorization': 'Bearer $token'},
        validateStatus: (_) => true,
        responseType: ResponseType.plain,
      ),
    );
    if (res.statusCode == 401) {
      await logout();
      throw TrackerAuthException(id, 'Session expired — sign in again');
    }
    return jsonDecode(res.data ?? '{}') as Map<String, dynamic>;
  }

  String _segment(MediaType type) => type == MediaType.manga ? 'manga' : 'anime';
  String _countField(MediaType type) =>
      type == MediaType.manga ? 'num_chapters' : 'num_episodes';

  @override
  Future<List<TrackSearchResult>> search(String query, MediaType type) async {
    final seg = _segment(type);
    final data = await _get('/$seg', {
      'q': query.length > 64 ? query.substring(0, 64) : query,
      'limit': 25,
      'fields': 'id,title,main_picture,synopsis,${_countField(type)}',
    });

    return (data?['data'] as List? ?? const []).map((raw) {
      final node = ((raw as Map)['node'] as Map).cast<String, dynamic>();
      return TrackSearchResult(
        remoteId: '${node['id']}',
        title: '${node['title']}',
        coverUrl: (node['main_picture'] as Map?)?['large'] as String? ??
            (node['main_picture'] as Map?)?['medium'] as String?,
        totalUnits: (node[_countField(type)] as int?) ?? 0,
        summary: node['synopsis'] as String?,
        remoteUrl: 'https://myanimelist.net/$seg/${node['id']}',
      );
    }).toList();
  }

  @override
  Future<TrackLink?> fetch(String remoteId, MediaType type) async {
    final seg = _segment(type);
    final statusField =
        type == MediaType.manga ? 'my_list_status' : 'my_list_status';
    final data = await _get('/$seg/$remoteId', {
      'fields': 'id,title,main_picture,${_countField(type)},$statusField',
    });
    if (data == null || data['id'] == null) return null;

    final status = (data[statusField] as Map?)?.cast<String, dynamic>();
    final progress = type == MediaType.manga
        ? (status?['num_chapters_read'] as int?)
        : (status?['num_episodes_watched'] as int?);

    return TrackLink(
      tracker: id,
      remoteId: '${data['id']}',
      title: '${data['title']}',
      status: _fromRemoteStatus(status?['status'] as String?),
      lastProgress: progress ?? 0,
      totalUnits: (data[_countField(type)] as int?) ?? 0,
      score: ((status?['score'] as num?) ?? 0).toDouble(),
      remoteUrl: 'https://myanimelist.net/$seg/${data['id']}',
      coverUrl: (data['main_picture'] as Map?)?['large'] as String?,
    );
  }

  @override
  Future<void> push(TrackLink link, MediaType type) async {
    await _refreshIfNeeded();
    final token = _tokens.accessToken(id);
    if (token == null) throw TrackerAuthException(id, 'Not signed in');

    final seg = _segment(type);
    final res = await _dio.put<String>(
      '$_api/$seg/${link.remoteId}/my_list_status',
      data: {
        'status': _toRemoteStatus(link.status, type),
        if (type == MediaType.manga)
          'num_chapters_read': link.lastProgress
        else
          'num_episodes_watched': link.lastProgress,
        'score': link.score.round(),
      },
      options: Options(
        headers: {'Authorization': 'Bearer $token'},
        contentType: Headers.formUrlEncodedContentType,
        validateStatus: (_) => true,
        responseType: ResponseType.plain,
      ),
    );

    if ((res.statusCode ?? 0) >= 400) {
      throw TrackerAuthException(id, 'Update rejected: ${res.data}');
    }
  }

  static TrackStatus _fromRemoteStatus(String? s) => switch (s) {
        'reading' || 'watching' => TrackStatus.reading,
        'plan_to_read' || 'plan_to_watch' => TrackStatus.planToRead,
        'completed' => TrackStatus.completed,
        'on_hold' => TrackStatus.onHold,
        'dropped' => TrackStatus.dropped,
        _ => TrackStatus.reading,
      };

  static String _toRemoteStatus(TrackStatus s, MediaType type) {
    final manga = type == MediaType.manga;
    return switch (s) {
      // MAL has no "rereading" status; it is a boolean flag alongside
      // "completed", so the closest honest mapping is the active state.
      TrackStatus.reading || TrackStatus.rereading =>
        manga ? 'reading' : 'watching',
      TrackStatus.planToRead => manga ? 'plan_to_read' : 'plan_to_watch',
      TrackStatus.completed => 'completed',
      TrackStatus.onHold => 'on_hold',
      TrackStatus.dropped => 'dropped',
    };
  }
}
