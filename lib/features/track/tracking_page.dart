import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../data/track/tracker.dart';
import '../../domain/models/track.dart';

/// Sign in to AniList / MyAnimeList and manage client IDs.
class TrackingPage extends ConsumerWidget {
  const TrackingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(trackingServiceProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Tracking')),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Link your library to AniList or MyAnimeList and progress is '
              'pushed automatically as you read.\n\n'
              'Both services require a client ID from an app you register '
              'yourself. This client ships without one on purpose: a shared '
              'ID in open-source code can be abused, and both services tie '
              'rate limits and bans to it.',
              style: TextStyle(fontSize: 13, height: 1.5),
            ),
          ),
          const Hairline(),
          for (final tracker in service.trackers)
            _TrackerTile(tracker: tracker),
        ],
      ),
    );
  }
}

class _TrackerTile extends ConsumerWidget {
  const _TrackerTile({required this.tracker});
  final Tracker tracker;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(trackingServiceProvider);
    final clientId = service.tokens.clientId(tracker.id);
    final hasClient = clientId != null && clientId.isNotEmpty;

    return Column(
      children: [
        ListTile(
          leading: Icon(
            tracker.isLoggedIn ? Icons.check_circle : Icons.link_off,
            color: tracker.isLoggedIn
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outline,
          ),
          title: Text(tracker.name),
          subtitle: Text(
            tracker.isLoggedIn
                ? 'Signed in${tracker.accountName != null ? ' as ${tracker.accountName}' : ''}'
                : hasClient
                    ? 'Client ID set — not signed in'
                    : 'No client ID configured',
          ),
          trailing: tracker.isLoggedIn
              ? TextButton(
                  onPressed: () => service.logout(tracker.id),
                  child: const Text('Sign out'),
                )
              : FilledButton(
                  onPressed: hasClient
                      ? () => _login(context, ref, tracker)
                      : null,
                  child: const Text('Sign in'),
                ),
        ),
        ListTile(
          dense: true,
          contentPadding: const EdgeInsets.only(left: 72, right: 16),
          title: Text(
            hasClient ? 'Client ID: $clientId' : 'Set client ID',
            style: const TextStyle(fontSize: 12.5),
          ),
          trailing: const Icon(Icons.edit_outlined, size: 18),
          onTap: () async {
            final value = await _promptClientId(context, tracker, clientId);
            if (value != null) await service.setClientId(tracker.id, value);
          },
        ),
        const Hairline(),
      ],
    );
  }

  Future<String?> _promptClientId(
      BuildContext context, Tracker tracker, String? current) {
    final controller = TextEditingController(text: current ?? '');
    final help = tracker.id == TrackerId.anilist
        ? 'AniList → Settings → Developer → Create New Client.\n'
            'Redirect URL must be:  https://anilist.co/api/v2/oauth/pin'
        : 'MyAnimeList → Account Settings → API → Create ID.\n'
            'App redirect URL must be:  kurayomi://mal-auth';

    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('${tracker.name} client ID'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(help, style: const TextStyle(fontSize: 12.5, height: 1.4)),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'Client ID'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _login(BuildContext context, WidgetRef ref, Tracker tracker) async {
    try {
      final url = tracker.authorizationUrl();
      final ok = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => OAuthPage(tracker: tracker, url: url),
        ),
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ok == true
              ? 'Signed in to ${tracker.name}'
              : 'Sign-in cancelled'),
        ));
      }
      ref.read(trackingServiceProvider).refreshState();
    } on TrackerAuthException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }
}

/// Runs an OAuth flow in a WebView and hands the redirect to the tracker.
class OAuthPage extends StatefulWidget {
  const OAuthPage({super.key, required this.tracker, required this.url});
  final Tracker tracker;
  final Uri url;

  @override
  State<OAuthPage> createState() => _OAuthPageState();
}

class _OAuthPageState extends State<OAuthPage> {
  bool _handled = false;
  double _progress = 0;

  /// Both services signal completion by navigating somewhere we recognise:
  /// AniList puts the token in a fragment, MAL uses our custom scheme.
  Future<bool> _maybeComplete(Uri? uri) async {
    if (uri == null || _handled) return false;
    final looksDone = uri.scheme == 'kurayomi' ||
        uri.fragment.contains('access_token') ||
        (uri.queryParameters['code'] != null &&
            uri.host.contains('myanimelist'));
    if (!looksDone) return false;

    _handled = true;
    try {
      final ok = await widget.tracker.handleRedirect(uri);
      if (mounted) Navigator.pop(context, ok);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
        Navigator.pop(context, false);
      }
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Sign in to ${widget.tracker.name}'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: _progress >= 1
              ? const SizedBox(height: 2)
              : LinearProgressIndicator(value: _progress, minHeight: 2),
        ),
      ),
      body: InAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(widget.url.toString())),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          thirdPartyCookiesEnabled: true,
          // The custom scheme redirect must reach us rather than erroring.
          useShouldOverrideUrlLoading: true,
        ),
        shouldOverrideUrlLoading: (controller, action) async {
          final uri = action.request.url;
          if (await _maybeComplete(uri)) return NavigationActionPolicy.CANCEL;
          return NavigationActionPolicy.ALLOW;
        },
        onProgressChanged: (_, p) => setState(() => _progress = p / 100),
        onLoadStop: (controller, uri) => _maybeComplete(uri),
        onUpdateVisitedHistory: (controller, uri, __) => _maybeComplete(uri),
      ),
    );
  }
}
