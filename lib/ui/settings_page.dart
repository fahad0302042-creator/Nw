import 'package:flutter/material.dart';

import '../app.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings'), centerTitle: false),
      body: ListView(
        children: <Widget>[
          const _SectionHeader('Reader'),
          SwitchListTile(
            title: const Text('Webtoon mode'),
            subtitle: const Text('Continuous vertical scrolling'),
            value: state.webtoonMode,
            onChanged: (value) => state.setSetting('webtoon', value),
          ),
          SwitchListTile(
            title: const Text('Right to left'),
            subtitle: const Text('Manga page order in paged mode'),
            value: state.rightToLeft,
            onChanged: (value) => state.setSetting('rtl', value),
          ),
          const Divider(),
          const _SectionHeader('Data'),
          ListTile(
            leading: const Icon(Icons.extension_outlined),
            title: const Text('Installed sources'),
            trailing: Text('${state.installed.length}'),
          ),
          ListTile(
            leading: const Icon(Icons.collections_bookmark_outlined),
            title: const Text('Library entries'),
            trailing: Text('${state.library.length}'),
          ),
          ListTile(
            leading: const Icon(Icons.history_toggle_off),
            title: const Text('Clear reading history'),
            subtitle: const Text('Forget read chapters and saved positions'),
            onTap: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Clear history?'),
                  content: const Text(
                    'Your library stays, but read markers and page positions '
                    'are removed.',
                  ),
                  actions: <Widget>[
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('Clear'),
                    ),
                  ],
                ),
              );
              if (confirmed == true) await state.clearProgress();
            },
          ),
          const Divider(),
          const _SectionHeader('About'),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Kuroyomi'),
            subtitle: Text(
              'A minimal, extension-driven reader. No content is bundled with '
              'the app — you choose which repositories to add.',
            ),
          ),
        ],
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
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              letterSpacing: 1.1,
            ),
      ),
    );
  }
}
