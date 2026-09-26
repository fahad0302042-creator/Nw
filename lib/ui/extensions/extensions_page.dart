import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/repo/extension_repository.dart';
import '../../core/source/source_manager.dart';
import '../../core/storage/app_storage.dart';
import '../../models/extension_summary.dart';

/// Lets the user paste in a repository index URL *or* a single extension
/// manifest URL, install/uninstall extensions, and manage saved
/// repositories. This screen is the concrete answer to "support extension
/// URLs and fetch sites from there".
class ExtensionsPage extends StatefulWidget {
  const ExtensionsPage({super.key});

  @override
  State<ExtensionsPage> createState() => _ExtensionsPageState();
}

class _ExtensionsPageState extends State<ExtensionsPage> {
  final _repository = const ExtensionRepository();
  final _urlController = TextEditingController();
  bool _addingUrl = false;

  final Map<String, List<ExtensionSummary>> _availableByRepo = {};
  final Map<String, Object?> _repoErrors = {};
  bool _loadingRepos = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshRepos());
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _refreshRepos() async {
    final storage = context.read<AppStorage>();
    setState(() => _loadingRepos = true);
    for (final repoUrl in storage.repos) {
      try {
        final result = await _repository.fetch(repoUrl);
        if (result.isRepo) {
          _availableByRepo[repoUrl] = result.extensions!;
          _repoErrors.remove(repoUrl);
        }
      } catch (e) {
        _repoErrors[repoUrl] = e;
      }
    }
    if (mounted) setState(() => _loadingRepos = false);
  }

  Future<void> _submitUrl() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;
    setState(() => _addingUrl = true);
    final storage = context.read<AppStorage>();
    final sourceManager = context.read<SourceManager>();
    try {
      final result = await _repository.fetch(url);
      if (result.isRepo) {
        await storage.addRepo(url);
        _availableByRepo[url] = result.extensions!;
        _urlController.clear();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Repository added (${result.extensions!.length} extensions found).')),
          );
        }
      } else {
        await sourceManager.installFromJson(result.singleManifest!.toJson());
        _urlController.clear();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Installed "${result.singleManifest!.name}".')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _addingUrl = false);
    }
  }

  Future<void> _install(ExtensionSummary summary) async {
    final sourceManager = context.read<SourceManager>();
    try {
      final manifest = await _repository.resolveManifest(summary);
      await sourceManager.installFromJson(manifest.toJson());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Installed "${manifest.name}".')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Install failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<AppStorage>();
    final sourceManager = context.watch<SourceManager>();

    return Scaffold(
      appBar: AppBar(title: const Text('Extensions')),
      body: RefreshIndicator(
        onRefresh: _refreshRepos,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Add repository or extension URL', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _urlController,
                          decoration: const InputDecoration(
                            hintText: 'https://.../index.json or .../source.json',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onSubmitted: (_) => _submitUrl(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _addingUrl ? null : _submitUrl,
                        child: _addingUrl
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Add'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Paste a repository index URL (lists many extensions) or a direct '
                    'link to a single extension\'s JSON manifest. See docs/EXTENSION_SPEC.md '
                    'to write your own.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            _SectionHeader('Installed (${sourceManager.installed.length})'),
            if (sourceManager.installed.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text('No extensions installed yet.'),
              ),
            ...sourceManager.installed.map(
              (ext) => ListTile(
                leading: CircleAvatar(child: Text(ext.type == 'anime' ? '📺' : '📖')),
                title: Text(ext.name),
                subtitle: Text('${ext.lang.toUpperCase()} \u00b7 v${ext.version} \u00b7 ${ext.type}'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => sourceManager.uninstall(ext.id),
                ),
              ),
            ),
            const Divider(height: 1),
            _SectionHeader('Repositories (${storage.repos.length})'),
            if (_loadingRepos) const LinearProgressIndicator(),
            if (storage.repos.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text('No repositories added yet.'),
              ),
            ...storage.repos.map((repoUrl) {
              final available = _availableByRepo[repoUrl] ?? [];
              final error = _repoErrors[repoUrl];
              return ExpansionTile(
                title: Text(repoUrl, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(error != null ? 'Failed to load: $error' : '${available.length} extensions'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    await storage.removeRepo(repoUrl);
                    _availableByRepo.remove(repoUrl);
                    _repoErrors.remove(repoUrl);
                    setState(() {});
                  },
                ),
                children: available
                    .map(
                      (summary) => ListTile(
                        leading: CircleAvatar(child: Text(summary.type == 'anime' ? '📺' : '📖')),
                        title: Text(summary.name),
                        subtitle: Text('${summary.lang.toUpperCase()} \u00b7 v${summary.version}'),
                        trailing: sourceManager.isInstalled(summary.id)
                            ? const Chip(label: Text('Installed'))
                            : FilledButton(
                                onPressed: () => _install(summary),
                                child: const Text('Install'),
                              ),
                      ),
                    )
                    .toList(),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(title, style: Theme.of(context).textTheme.titleSmall),
    );
  }
}
