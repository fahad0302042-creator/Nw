import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../extensions/extension_repository.dart';
import '../../domain/models/media.dart';
import '../../extensions/extension.dart';
import '../common/widgets.dart';

/// Install / update / remove extensions, and manage repository URLs.
class ExtensionsPage extends ConsumerStatefulWidget {
  const ExtensionsPage({super.key});
  @override
  ConsumerState<ExtensionsPage> createState() => _ExtensionsPageState();
}

class _ExtensionsPageState extends ConsumerState<ExtensionsPage> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final manager = ref.watch(extensionManagerProvider);
    final installed = manager.installed;
    final available = manager.available;
    final updates = manager.updates;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Extensions'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh repositories',
            onPressed: _busy ? null : () => _run(manager.refreshRepos),
          ),
          IconButton(
            icon: const Icon(Icons.dns_outlined),
            tooltip: 'Repositories',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ReposPage()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: (installed.isEmpty && available.isEmpty)
                ? EmptyState(
                    icon: Icons.dns_outlined,
                    title: 'No repositories yet',
                    message:
                        'Add a repository URL pointing at an index.json to see '
                        'installable extensions.',
                    action: FilledButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ReposPage()),
                      ),
                      icon: const Icon(Icons.add),
                      label: const Text('Add repository'),
                    ),
                  )
                : ListView(
                    children: [
                      if (updates.isNotEmpty) ...[
                        _header(context, 'Updates (${updates.length})'),
                        for (final e in updates)
                          _tile(
                            e,
                            trailing: FilledButton(
                              onPressed:
                                  _busy ? null : () => _run(() => manager.update(e)),
                              child: const Text('Update'),
                            ),
                          ),
                      ],
                      if (installed.isNotEmpty)
                        _header(context, 'Installed (${installed.length})'),
                      for (final e in installed)
                        _tile(
                          e,
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            tooltip: 'Uninstall',
                            onPressed: _busy
                                ? null
                                : () => _run(() => manager.uninstall(e.id)),
                          ),
                        ),
                      if (available.isNotEmpty)
                        _header(context, 'Available (${available.length})'),
                      for (final e in available)
                        _tile(
                          e,
                          trailing: OutlinedButton(
                            onPressed:
                                _busy ? null : () => _run(() => manager.install(e)),
                            child: const Text('Install'),
                          ),
                        ),
                      if (manager.lastError != null)
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            manager.lastError!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      const SizedBox(height: 24),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
        child: Text(
          text,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(color: Theme.of(context).colorScheme.primary),
        ),
      );

  Widget _tile(ExtensionInfo e, {required Widget trailing}) => ListTile(
        leading: SizedBox(
          width: 40,
          height: 40,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: e.iconUrl != null
                ? CoverImage(url: e.iconUrl, fit: BoxFit.contain)
                : Container(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    alignment: Alignment.center,
                    child: Icon(
                      e.type.name == 'anime'
                          ? Icons.movie_outlined
                          : Icons.menu_book_outlined,
                      size: 20,
                    ),
                  ),
          ),
        ),
        title: Text(e.name),
        subtitle: Text(
          '${e.lang.toUpperCase()} · v${e.version} · ${e.type.label}'
          '${e.nsfw ? ' · 18+' : ''}',
        ),
        trailing: trailing,
      );
}

/// Manage the list of repository index URLs.
class ReposPage extends ConsumerStatefulWidget {
  const ReposPage({super.key});
  @override
  ConsumerState<ReposPage> createState() => _ReposPageState();
}

class _ReposPageState extends ConsumerState<ReposPage> {
  bool _busy = false;

  Future<void> _addDialog() async {
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add repository'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                hintText: 'https://example.com/repo/index.json',
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'The URL must point at an index.json file listing JavaScript '
              'extensions.\n\n'
              'A GitHub page link is fixed up automatically, and a folder URL '
              'gets /index.json appended.\n\n'
              'Keiyoushi and Aniyomi .apk repositories will not work — those '
              'extensions are compiled Android code.',
              style: TextStyle(fontSize: 12, height: 1.45),
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
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (url == null || url.isEmpty) return;

    setState(() => _busy = true);
    try {
      await ref.read(extensionManagerProvider).addRepo(url);
    } catch (e) {
      // These messages are written to be read — a snackbar would clip them.
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Could not add repository'),
            content: SingleChildScrollView(
              child: Text(
                e is RepoException ? e.message : '$e',
                style: const TextStyle(fontSize: 13.5, height: 1.45),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final manager = ref.watch(extensionManagerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Repositories')),
      floatingActionButton: FloatingActionButton(
        onPressed: _busy ? null : _addDialog,
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: manager.repoUrls.isEmpty
                ? const EmptyState(
                    icon: Icons.dns_outlined,
                    title: 'No repositories',
                    message:
                        'A repository is a URL to an index.json listing extensions.',
                  )
                : ListView(
                    children: [
                      for (final url in manager.repoUrls)
                        ListTile(
                          leading: const Icon(Icons.link),
                          title: Text(url, style: const TextStyle(fontSize: 13)),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => manager.removeRepo(url),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
