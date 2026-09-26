import 'package:flutter/material.dart';

import '../app.dart';
import '../extensions/manifest.dart';
import 'widgets/media_grid.dart';

class ExtensionsPage extends StatefulWidget {
  const ExtensionsPage({super.key});

  @override
  State<ExtensionsPage> createState() => _ExtensionsPageState();
}

class _ExtensionsPageState extends State<ExtensionsPage> {
  final TextEditingController _url = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _add(String raw) async {
    final url = raw.trim();
    if (url.isEmpty) return;
    setState(() => _busy = true);
    try {
      final result = await AppScope.read(context).addRepo(url);
      if (!mounted) return;
      _url.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Added "${result.info.name}" · ${result.sources.length} sources',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Could not add repository'),
          content: SingleChildScrollView(child: Text(error.toString())),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refresh(String url) async {
    setState(() => _busy = true);
    try {
      await AppScope.read(context).refreshRepo(url);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Refresh failed: $error')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Extensions'), centerTitle: false),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: <Widget>[
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: 'Extension repository url',
              hintText: 'https://raw.githubusercontent.com/.../index.json',
              suffixIcon: IconButton(
                icon: const Icon(Icons.add),
                onPressed: _busy ? null : () => _add(_url.text),
              ),
            ),
            onSubmitted: _busy ? null : _add,
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Paste the raw json url of a repository. GitHub "blob" links '
                  'are converted automatically.',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.white54),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _busy ? null : () => _add(kDemoRepoUrl),
              icon: const Icon(Icons.science_outlined, size: 18),
              label: const Text('Load demo repository'),
            ),
          ),
          if (_busy) const LinearProgressIndicator(),
          const SizedBox(height: 8),
          if (state.repos.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: StatusView(
                icon: Icons.cloud_download_outlined,
                title: 'No repositories yet',
                message:
                    'Add a repository url above, or load the demo repository '
                    'to see how everything works.',
              ),
            ),
          for (final repo in state.repos) _RepoSection(
            repo: repo,
            onRefresh: () => _refresh(repo.url),
          ),
        ],
      ),
    );
  }
}

/// Demo repository shipped with the project (safe, no third party sites).
const String kDemoRepoUrl =
    'https://raw.githubusercontent.com/fahad0302042-creator/Nw/arena/01a0dbdc-nw/example_repo/index.json';

class _RepoSection extends StatelessWidget {
  const _RepoSection({required this.repo, required this.onRefresh});

  final RepoInfo repo;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final sources = state.catalogue[repo.url];

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        repo.name,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Text(
                        repo.url,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Colors.white38),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Reload',
                  icon: const Icon(Icons.refresh),
                  onPressed: onRefresh,
                ),
                IconButton(
                  tooltip: 'Remove',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => state.removeRepo(repo.url),
                ),
              ],
            ),
            const Divider(),
            if (sources == null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.info_outline, size: 16, color: Colors.white38),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Tap reload to fetch the ${repo.sourceCount} sources.',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Colors.white54),
                      ),
                    ),
                  ],
                ),
              )
            else
              for (final source in sources)
                _SourceTile(source: source, installed: state.isInstalled(source.id)),
          ],
        ),
      ),
    );
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({required this.source, required this.installed});

  final SourceManifest source;
  final bool installed;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(
        source.isAnime ? Icons.movie_outlined : Icons.menu_book_outlined,
        color: source.isAnime ? Colors.deepPurple.shade200 : Colors.teal.shade200,
      ),
      title: Text(source.name),
      subtitle: Text(
        '${source.type} · ${source.lang.toUpperCase()} · v${source.version}'
        '${source.nsfw ? ' · 18+' : ''}',
      ),
      trailing: installed
          ? TextButton(
              onPressed: () => state.uninstallSource(source.id),
              child: const Text('Remove'),
            )
          : FilledButton.tonal(
              onPressed: () => state.installSource(source),
              child: const Text('Install'),
            ),
    );
  }
}
