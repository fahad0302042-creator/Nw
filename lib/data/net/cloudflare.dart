import 'package:dio/dio.dart';

/// Recognises anti-bot interstitials in an HTTP response.
///
/// Cloudflare is the common case, but DDoS-Guard and Sucuri use the same
/// pattern (a 403/503 carrying an HTML challenge page), and they are all
/// solved the same way: render it in a real browser engine.
class ChallengeDetector {
  static const _bodyMarkers = [
    '_cf_chl_opt',
    'cf-browser-verification',
    'challenge-platform',
    'Just a moment',
    'Checking your browser before accessing',
    'cf_chl_prog',
    'DDoS-Guard',
    'ddos-guard',
    'sucuri_cloudproxy',
  ];

  /// True when [response] is a challenge rather than real content.
  static bool isChallenge(Response response) {
    final status = response.statusCode ?? 0;

    // Cloudflare labels its own interstitials since 2023 — cheapest signal.
    final mitigated = response.headers.value('cf-mitigated');
    if (mitigated != null && mitigated.toLowerCase().contains('challenge')) {
      return true;
    }

    if (status != 403 && status != 503 && status != 429) return false;

    final server = (response.headers.value('server') ?? '').toLowerCase();
    final body = response.data is String ? response.data as String : '';

    // A 403 from Cloudflare with an HTML body is almost always a challenge;
    // a 403 with a JSON body is a genuine authorisation failure, so we must
    // not send the user to a WebView for it.
    final looksHtml = body.trimLeft().startsWith('<') ||
        (response.headers.value('content-type') ?? '').contains('text/html');
    if (!looksHtml) return false;

    if (_bodyMarkers.any(body.contains)) return true;
    return server.contains('cloudflare') && status == 503;
  }

  /// Human-readable label for the challenge UI.
  static String describe(Response response) {
    final body = response.data is String ? response.data as String : '';
    if (body.contains('DDoS-Guard') || body.contains('ddos-guard')) {
      return 'DDoS-Guard';
    }
    if (body.contains('sucuri_cloudproxy')) return 'Sucuri';
    return 'Cloudflare';
  }
}

/// Thrown when a challenge could not be solved (user cancelled, timed out,
/// or the app has no UI attached to open a WebView in).
class ChallengeFailedException implements Exception {
  ChallengeFailedException(this.url, this.reason);
  final String url;
  final String reason;

  @override
  String toString() => 'Could not pass the browser check for $url: $reason';
}
