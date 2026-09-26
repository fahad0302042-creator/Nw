import 'dart:convert';

import 'package:http/http.dart' as http;

/// Thin HTTP helper shared by the extension engine.
class Net {
  Net._();

  static final http.Client _client = http.Client();

  static const String defaultUserAgent =
      'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/122.0.0.0 Mobile Safari/537.36';

  static Map<String, String> buildHeaders(Map<String, String>? extra) {
    final headers = <String, String>{
      'User-Agent': defaultUserAgent,
      'Accept': '*/*',
      'Accept-Language': 'en-US,en;q=0.9',
    };
    if (extra != null) {
      extra.forEach((key, value) => headers[key] = value);
    }
    return headers;
  }

  /// Fetches [url] and returns the body decoded as UTF-8.
  static Future<String> fetch(
    String url, {
    Map<String, String>? headers,
    String method = 'GET',
    String? body,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final uri = Uri.parse(url);
    final requestHeaders = buildHeaders(headers);
    final http.Response response;
    if (method.toUpperCase() == 'POST') {
      requestHeaders.putIfAbsent(
        'Content-Type',
        () => 'application/x-www-form-urlencoded',
      );
      response = await _client
          .post(uri, headers: requestHeaders, body: body)
          .timeout(timeout);
    } else {
      response = await _client.get(uri, headers: requestHeaders).timeout(timeout);
    }
    if (response.statusCode < 200 || response.statusCode >= 400) {
      throw HttpFailure(response.statusCode, url);
    }
    return utf8.decode(response.bodyBytes, allowMalformed: true);
  }
}

class HttpFailure implements Exception {
  HttpFailure(this.statusCode, this.url);

  final int statusCode;
  final String url;

  @override
  String toString() => 'Request failed (HTTP $statusCode)\n$url';
}
