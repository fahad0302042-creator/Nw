import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Persistent, per-host cookie jar shared by the HTTP client and the WebView.
///
/// This is the single most important piece of the Cloudflare story: a
/// `cf_clearance` cookie is only valid for the exact (IP, User-Agent, cookie)
/// triple that solved the challenge. So the cookies the WebView earns must be
/// replayed byte-for-byte by Dio, together with the same User-Agent — which
/// is why [userAgentFor] lives here too rather than being a global constant.
class CookieStore {
  CookieStore._(this._prefs);

  static CookieStore? _instance;
  static Future<CookieStore> instance() async =>
      _instance ??= CookieStore._(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;

  static const _kCookies = 'net_cookies';
  static const _kAgents = 'net_user_agents';

  /// Chrome-on-Android. Must stay plausible: Cloudflare fingerprints the UA
  /// against TLS/HTTP2 characteristics and rejects obvious mismatches.
  static const defaultUserAgent =
      'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';

  Map<String, dynamic> _read(String key) {
    final raw = _prefs.getString(key);
    if (raw == null || raw.isEmpty) return {};
    try {
      return (jsonDecode(raw) as Map).cast<String, dynamic>();
    } catch (_) {
      return {};
    }
  }

  Future<void> _write(String key, Map<String, dynamic> value) =>
      _prefs.setString(key, jsonEncode(value));

  static String hostOf(String url) {
    try {
      return Uri.parse(url).host.toLowerCase();
    } catch (_) {
      return '';
    }
  }

  // ---------------------------------------------------------------- cookies

  /// Cookies for [url] as a ready-to-send `Cookie:` header value.
  String? cookieHeader(String url) {
    final jar = _jarFor(hostOf(url));
    if (jar.isEmpty) return null;
    return jar.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  Map<String, String> _jarFor(String host) {
    if (host.isEmpty) return {};
    final all = _read(_kCookies);
    final out = <String, String>{};

    // Match the host and any parent domain, so cookies set on
    // ".example.com" are sent to "www.example.com" as a browser would.
    for (final entry in all.entries) {
      final stored = entry.key;
      if (host == stored || host.endsWith('.$stored')) {
        out.addAll((entry.value as Map).cast<String, String>());
      }
    }
    return out;
  }

  Future<void> saveCookies(String url, Map<String, String> cookies) async {
    final host = hostOf(url);
    if (host.isEmpty || cookies.isEmpty) return;
    final all = _read(_kCookies);
    final jar = ((all[host] as Map?)?.cast<String, String>() ?? {})
      ..addAll(cookies);
    all[host] = jar;
    await _write(_kCookies, all);
  }

  /// Merges `Set-Cookie` response headers into the jar.
  Future<void> ingestSetCookie(String url, List<String> setCookieHeaders) async {
    if (setCookieHeaders.isEmpty) return;
    final parsed = <String, String>{};
    for (final raw in setCookieHeaders) {
      final first = raw.split(';').first.trim();
      final eq = first.indexOf('=');
      if (eq <= 0) continue;
      parsed[first.substring(0, eq)] = first.substring(eq + 1);
    }
    await saveCookies(url, parsed);
  }

  bool hasClearance(String url) =>
      _jarFor(hostOf(url)).containsKey('cf_clearance');

  Future<void> clearHost(String url) async {
    final all = _read(_kCookies);
    all.remove(hostOf(url));
    await _write(_kCookies, all);
  }

  Future<void> clearAll() async {
    await _prefs.remove(_kCookies);
    await _prefs.remove(_kAgents);
  }

  // ------------------------------------------------------------- user agent

  /// The UA that solved the challenge for this host, if any.
  String userAgentFor(String url) =>
      (_read(_kAgents)[hostOf(url)] as String?) ?? defaultUserAgent;

  Future<void> saveUserAgent(String url, String ua) async {
    if (ua.trim().isEmpty) return;
    final all = _read(_kAgents);
    all[hostOf(url)] = ua;
    await _write(_kAgents, all);
  }

  /// Hosts we currently hold cookies for — surfaced in settings.
  List<String> get knownHosts => _read(_kCookies).keys.toList()..sort();
}
