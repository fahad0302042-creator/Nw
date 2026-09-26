import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/track.dart';

/// Persists OAuth credentials and the user-supplied client IDs.
///
/// Client IDs are a user setting rather than a baked-in constant: shipping
/// one in an open-source client means anyone can impersonate the app, and
/// both services tie rate limits and revocation to it.
class TokenStore {
  TokenStore._(this._prefs);

  static TokenStore? _instance;
  static Future<TokenStore> instance() async =>
      _instance ??= TokenStore._(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;

  String _key(TrackerId t, String field) => 'track_${t.name}_$field';

  String? clientId(TrackerId t) => _prefs.getString(_key(t, 'client_id'));
  Future<void> setClientId(TrackerId t, String value) =>
      _prefs.setString(_key(t, 'client_id'), value.trim());

  String? accessToken(TrackerId t) => _prefs.getString(_key(t, 'access'));
  String? refreshToken(TrackerId t) => _prefs.getString(_key(t, 'refresh'));
  String? accountName(TrackerId t) => _prefs.getString(_key(t, 'account'));

  DateTime? expiry(TrackerId t) {
    final ms = _prefs.getInt(_key(t, 'expires_at'));
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  bool isExpired(TrackerId t) {
    final e = expiry(t);
    // A minute of slack so a token does not expire mid-request.
    return e != null && e.isBefore(DateTime.now().add(const Duration(minutes: 1)));
  }

  Future<void> saveTokens(
    TrackerId t, {
    required String access,
    String? refresh,
    Duration? expiresIn,
    String? account,
  }) async {
    await _prefs.setString(_key(t, 'access'), access);
    if (refresh != null) await _prefs.setString(_key(t, 'refresh'), refresh);
    if (account != null) await _prefs.setString(_key(t, 'account'), account);
    if (expiresIn != null) {
      await _prefs.setInt(_key(t, 'expires_at'),
          DateTime.now().add(expiresIn).millisecondsSinceEpoch);
    }
  }

  Future<void> clear(TrackerId t) async {
    for (final f in ['access', 'refresh', 'account', 'expires_at']) {
      await _prefs.remove(_key(t, f));
    }
  }

  /// Verifier for the PKCE flow, held between the two legs of the handshake.
  Future<void> setPkceVerifier(TrackerId t, String v) =>
      _prefs.setString(_key(t, 'pkce'), v);
  String? pkceVerifier(TrackerId t) => _prefs.getString(_key(t, 'pkce'));

  Map<String, dynamic> exportSettings() => {
        for (final t in TrackerId.values)
          if (clientId(t) != null) t.name: clientId(t),
      };

  Future<void> importSettings(Map<String, dynamic> data) async {
    for (final entry in data.entries) {
      final t = TrackerId.parse(entry.key);
      if (t != null) await setClientId(t, '${entry.value}');
    }
  }

  @override
  String toString() => jsonEncode(exportSettings());
}
