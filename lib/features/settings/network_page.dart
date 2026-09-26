import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../data/net/app_http_client.dart';
import '../../data/net/cookie_store.dart';
import '../webview/challenge_page.dart';

/// Inspect and reset the browser state the app has accumulated.
///
/// Stale `cf_clearance` cookies are the single most common cause of a source
/// that "worked yesterday", so clearing them needs to be one tap away.
class NetworkPage extends ConsumerStatefulWidget {
  const NetworkPage({super.key});
  @override
  ConsumerState<NetworkPage> createState() => _NetworkPageState();
}

class _NetworkPageState extends ConsumerState<NetworkPage> {
  List<String> _hosts = const [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final store = await CookieStore.instance();
    if (mounted) setState(() => _hosts = store.knownHosts);
  }

  Future<void> _clearAll() async {
    final store = await CookieStore.instance();
    await store.clearAll();
    await CookieManager.instance().deleteAllCookies();
    await _refresh();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cookies and WebView data cleared')),
      );
    }
  }

  Future<void> _openManually() async {
    final controller = TextEditingController(text: 'https://');
    final url = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Open in browser'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(hintText: 'https://example.com'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Open'),
          ),
        ],
      ),
    );
    if (url == null || url.length < 8 || !mounted) return;

    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ChallengePage(url: url, label: 'Browser'),
      ),
    );
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final client = AppHttpClient.current;

    return Scaffold(
      appBar: AppBar(title: const Text('Network & browser')),
      body: ListView(
        children: [
          _label('CLOUDFLARE'),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              'When a source is behind a browser check, a WebView opens '
              'automatically, solves it, and the resulting clearance cookie is '
              'reused for normal requests. Clearance is tied to your IP and '
              'User-Agent, and expires on its own after a while.',
              style: TextStyle(fontSize: 13, height: 1.5),
            ),
          ),
          const Hairline(),
          ListTile(
            leading: const Icon(Icons.travel_explore),
            title: const Text('Open a site manually'),
            subtitle: const Text('Solve a check or log in ahead of time'),
            onTap: _openManually,
          ),
          const Hairline(indent: 16),
          ListTile(
            leading: const Icon(Icons.delete_sweep_outlined),
            title: const Text('Clear cookies & WebView data'),
            subtitle: const Text('Fixes sources that suddenly stopped working'),
            onTap: _clearAll,
          ),
          const Hairline(),
          _label('STORED COOKIES (${_hosts.length})'),
          if (_hosts.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text('No cookies stored yet.',
                  style: TextStyle(fontSize: 13)),
            ),
          for (final host in _hosts)
            ListTile(
              dense: true,
              leading: Icon(
                client?.cookies.hasClearance('https://$host') == true
                    ? Icons.verified_user_outlined
                    : Icons.cookie_outlined,
                size: 20,
              ),
              title: Text(host, style: const TextStyle(fontSize: 14)),
              subtitle: client?.cookies.hasClearance('https://$host') == true
                  ? const Text('Cloudflare clearance held')
                  : null,
              trailing: IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () async {
                  final store = await CookieStore.instance();
                  await store.clearHost('https://$host');
                  await _refresh();
                },
              ),
            ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 22, 16, 10),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall),
      );
}
