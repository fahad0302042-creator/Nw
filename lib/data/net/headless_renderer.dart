import 'dart:async';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'cookie_store.dart';

/// Runs a page in an off-screen WebView and returns the DOM *after*
/// JavaScript has executed.
///
/// Needed for the growing number of sources that render their chapter lists
/// or video links client-side, where fetching the HTML yields an empty shell.
/// Unlike [ChallengePage] this shows no UI, so it must never be used for an
/// interactive challenge — only for JS-rendered content.
class HeadlessRenderer {
  /// Loads [url] and resolves with its HTML.
  ///
  /// If [waitForSelector] is given, resolution waits until that CSS selector
  /// matches at least one node — far more reliable than a fixed delay.
  static Future<String> render(
    String url, {
    String? waitForSelector,
    Duration timeout = const Duration(seconds: 30),
    Map<String, String> headers = const {},
  }) async {
    final completer = Completer<String>();
    final store = await CookieStore.instance();

    HeadlessInAppWebView? webView;
    Timer? poll;
    Timer? deadline;

    Future<void> cleanUp() async {
      poll?.cancel();
      deadline?.cancel();
      try {
        await webView?.dispose();
      } catch (_) {}
    }

    void succeed(String html) {
      if (completer.isCompleted) return;
      completer.complete(html);
      cleanUp();
    }

    void fail(Object error) {
      if (completer.isCompleted) return;
      completer.completeError(error);
      cleanUp();
    }

    Future<String?> readHtml(InAppWebViewController c) async {
      final result = await c.evaluateJavascript(
        source: 'document.documentElement.outerHTML',
      );
      return result is String ? result : null;
    }

    webView = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(
        url: WebUri(url),
        headers: headers,
      ),
      initialSettings: InAppWebViewSettings(
        userAgent: store.userAgentFor(url),
        javaScriptEnabled: true,
        thirdPartyCookiesEnabled: true,
        // Images are irrelevant when we only want the DOM, and skipping them
        // makes rendering dramatically faster and cheaper on mobile data.
        blockNetworkImage: true,
        loadsImagesAutomatically: false,
      ),
      onLoadStop: (c, _) async {
        if (waitForSelector == null) {
          final html = await readHtml(c);
          if (html != null) succeed(html);
          return;
        }

        poll ??= Timer.periodic(const Duration(milliseconds: 300), (_) async {
          try {
            final found = await c.evaluateJavascript(
              source: '!!document.querySelector(${_jsString(waitForSelector)})',
            );
            if (found == true || found == 'true') {
              final html = await readHtml(c);
              if (html != null) succeed(html);
            }
          } catch (_) {}
        });
      },
      onReceivedError: (_, __, err) => fail(StateError(err.description)),
    );

    deadline = Timer(timeout, () async {
      // Prefer returning whatever rendered over failing outright — a partial
      // DOM is usually still parseable.
      try {
        final c = webView?.webViewController;
        final html = c == null ? null : await readHtml(c);
        if (html != null && html.length > 200) {
          succeed(html);
          return;
        }
      } catch (_) {}
      fail(TimeoutException('Rendering $url timed out'));
    });

    await webView.run();
    return completer.future;
  }

  static String _jsString(String s) =>
      '"${s.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
}
