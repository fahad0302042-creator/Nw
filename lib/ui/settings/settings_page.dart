import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  PackageInfo? _info;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((v) => setState(() => _info = v));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('About Tsundoku'),
            subtitle: Text(
              'A minimal, open-source manga & anime reader with a '
              'no-code, JSON-based extension system. Bring your own sources.',
            ),
          ),
          if (_info != null)
            ListTile(
              leading: const Icon(Icons.numbers),
              title: const Text('Version'),
              subtitle: Text('${_info!.version} (build ${_info!.buildNumber})'),
            ),
          ListTile(
            leading: const Icon(Icons.cleaning_services_outlined),
            title: const Text('Clear image cache'),
            subtitle: const Text('Frees space used by cached covers and pages'),
            onTap: () async {
              await DefaultCacheManager().emptyCache();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Image cache cleared.')),
                );
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('Extension format documentation'),
            subtitle: const Text('docs/EXTENSION_SPEC.md in the project repository'),
            onTap: () => launchUrl(
              Uri.parse(
                'https://github.com/fahad0302042-creator/Nw/blob/main/docs/EXTENSION_SPEC.md',
              ),
              mode: LaunchMode.externalApplication,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.code),
            title: const Text('Source code'),
            subtitle: const Text('github.com/fahad0302042-creator/Nw'),
            onTap: () => launchUrl(
              Uri.parse('https://github.com/fahad0302042-creator/Nw'),
              mode: LaunchMode.externalApplication,
            ),
          ),
        ],
      ),
    );
  }
}
