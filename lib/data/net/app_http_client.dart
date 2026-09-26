import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../core/app_keys.dart';
import '../../features/webview/challenge_page.dart';
import 'cloudflare.dart';
import 'cookie_store.dart';

/// The single HTTP client every extension request goes through.
///
/// Responsibilities, in order:
///   1. attach stored cookies + the host-pinned User-Agent
///   2. persist any `Set-Cookie` the server returns
///   3. detect an anti-bot interstitial, solve it in a WebView, and retry once
///
/// Solving is de-duplicated per host: if twenty page-image requests hit a
/// challenge simultaneously, exactly one WebView opens and the other
/// nineteen await the same future.
class AppHttpClient {
  AppHttpClient._(this._dio, this._cookies);

  final Dio _dio;
  final CookieStore _cookies;

  static AppHttpClient? _instance;
  static final Map<String, Future<bool>> _solving = {};

  /// Set to false for contexts where we must never show UI (e.g. background
  /// library updates); challenges then fail fast instead of hanging.
  static bool interactive = true;

  static Future<AppHttpClient> instance() async {
    if (_instance != null) return _instance!;
    final cookies = await CookieStore.instance();
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 30),
      followRedirects: true,
      maxRedirects: 5,
      validateStatus: (_) => true,
      responseType: ResponseType.plain,
    ));
    return _instance = AppHttpClient._(dio, cookies);
  }

  CookieStore get cookies => _cookies;

  /// Non-null once [instance] has completed. Used by sync call-sites such as
  /// image widgets that need cookie headers but cannot await.
  static AppHttpClient? get current => _instance;

  Future<Response<String>> request(
    String url, {
    String method = 'GET',
    Map<String, String> headers = const {},
    Object? body,
    bool allowChallengeSolving = true,
  }) async {
    var response = await _send(url, method, headers, body);

    if (allowChallengeSolving && ChallengeDetector.isChallenge(response)) {
      final passed = await _solveChallenge(
        url,
        ChallengeDetector.describe(response),
      );
      if (!passed) {
        throw ChallengeFailedException(
          url,
          interactive ? 'not completed' : 'no UI available to solve it',
        );
      }
      // Retry exactly once with the freshly earned clearance.
      response = await _send(url, method, headers, body);

      if (ChallengeDetector.isChallenge(response)) {
        // Stale clearance for this host: drop it so the next attempt is clean.
        await _cookies.clearHost(url);
        throw ChallengeFailedException(url, 'challenge returned after solving');
      }
    }

    return response;
  }

  Future<Response<String>> _send(
    String url,
    String method,
    Map<String, String> headers,
    Object? body,
  ) async {
    final merged = <String, String>{
      'User-Agent': _cookies.userAgentFor(url),
      'Accept':
          'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,'
              'image/webp,*/*;q=0.8',
      'Accept-Language': 'en-US,en;q=0.9',
      ...headers,
    };

    final jar = _cookies.cookieHeader(url);
    if (jar != null && !merged.containsKey('Cookie')) {
      merged['Cookie'] = jar;
    }

    final res = await _dio.request<String>(
      url,
      data: body,
      options: Options(method: method, headers: merged),
    );

    final setCookie = res.headers.map['set-cookie'];
    if (setCookie != null && setCookie.isNotEmpty) {
      await _cookies.ingestSetCookie(res.realUri.toString(), setCookie);
    }

    return res;
  }

  Future<bool> _solveChallenge(String url, String label) {
    final host = CookieStore.hostOf(url);

    // Another request already opened a WebView for this host — join it.
    final inFlight = _solving[host];
    if (inFlight != null) return inFlight;

    final future = _openSolver(url, label).whenComplete(() {
      _solving.remove(host);
    });
    _solving[host] = future;
    return future;
  }

  Future<bool> _openSolver(String url, String label) async {
    if (!interactive) return false;
    final nav = rootNavigatorKey.currentState;
    if (nav == null) return false;

    final result = await nav.push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ChallengePage(url: url, label: label),
      ),
    );
    return result == true;
  }

  /// Headers an image loader or video player must replay to stay authorised.
  Map<String, String> mediaHeadersFor(String url, {String? referer}) {
    final headers = <String, String>{
      'User-Agent': _cookies.userAgentFor(url),
      if (referer != null && referer.isNotEmpty) 'Referer': referer,
    };
    final jar = _cookies.cookieHeader(url);
    if (jar != null) headers['Cookie'] = jar;
    return headers;
  }
}
