import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../data/net/cookie_store.dart';

/// Renders an anti-bot challenge in a real browser engine and harvests the
/// cookies it produces.
///
/// Cloudflare's JS challenge is designed to be unsolvable by an HTTP client:
/// it runs WebAssembly, times canvas operations and inspects the JS
/// environment. The only reliable answer is to let a genuine WebView run it,
/// then reuse the resulting `cf_clearance` cookie — pinned to the same
/// User-Agent — for subsequent Dio requests.
class ChallengePage extends StatefulWidget {
  const ChallengePage({
    super.key,
    required this.url,
    this.label = 'Cloudflare',
    this.timeout = const Duration(seconds: 60),
  });

  final String url;
  final String label;
  final Duration timeout;

  @override
  State<ChallengePage> createState() => _ChallengePageState();
}

class _ChallengePageState extends State<ChallengePage> {
  InAppWebViewController? _controller;
  Timer? _poll;
  Timer? _deadline;
  bool _finished = false;
  String _status = 'Starting browser…';
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _deadline = Timer(widget.timeout, () {
      if (!_finished) _finish(false, 'Timed out');
    });
    // Poll rather than relying on onLoadStop: Cloudflare's challenge does
    // several same-page transitions and may never fire a clean final load.
    _poll = Timer.periodic(const Duration(milliseconds: 700), (_) => _check());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _deadline?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    final c = _controller;
    if (c == null || _finished) return;

    try {
      final current = await c.getUrl();
      final target = WebUri(current?.toString() ?? widget.url);

      final cookies = await CookieManager.instance().getCookies(url: target);
      final map = {for (final k in cookies) k.name: '${k.value}'};

      final solved = map.containsKey('cf_clearance') ||
          map.containsKey('__ddg1_') ||
          map.containsKey('__ddg2_');

      if (!solved) return;

      // The clearance cookie is bound to the UA that earned it.
      final ua = await c.evaluateJavascript(source: 'navigator.userAgent');

      final store = await CookieStore.instance();
      await store.saveCookies(target.toString(), map);
      if (ua is String && ua.isNotEmpty) {
        await store.saveUserAgent(target.toString(), ua);
      }
      _finish(true, 'Verified');
    } catch (_) {
      // Transient errors while the page is mid-navigation are expected.
    }
  }

  void _finish(bool ok, String reason) {
    if (_finished) return;
    _finished = true;
    _poll?.cancel();
    _deadline?.cancel();
    if (mounted) Navigator.of(context).pop(ok);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _finish(false, 'Cancelled');
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => _finish(false, 'Cancelled'),
          ),
          title: Text('${widget.label} check'),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(2),
            child: _progress >= 1
                ? const SizedBox(height: 2)
                : LinearProgressIndicator(value: _progress, minHeight: 2),
          ),
        ),
        body: Column(
          children: [
            Container(
              width: double.infinity,
              color: scheme.surfaceContainerHighest,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text(
                _status,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ),
            Expanded(
              child: InAppWebView(
                initialUrlRequest: URLRequest(url: WebUri(widget.url)),
                initialSettings: InAppWebViewSettings(
                  userAgent: CookieStore.defaultUserAgent,
                  javaScriptEnabled: true,
                  thirdPartyCookiesEnabled: true,
                  useShouldInterceptRequest: false,
                  clearCache: false,
                  // A challenge served to a "desktop" viewport on a phone UA
                  // is a mismatch Cloudflare notices.
                  useWideViewPort: false,
                ),
                onWebViewCreated: (c) => _controller = c,
                onProgressChanged: (_, p) =>
                    setState(() => _progress = p / 100),
                onLoadStop: (c, url) async {
                  final title = await c.getTitle() ?? '';
                  if (!mounted) return;
                  setState(() => _status = title.toLowerCase().contains('just a moment')
                      ? 'Solving the challenge — this usually takes a few seconds…'
                      : 'Loaded: $title');
                  _check();
                },
                onReceivedError: (_, __, err) {
                  if (mounted) setState(() => _status = 'Error: ${err.description}');
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
