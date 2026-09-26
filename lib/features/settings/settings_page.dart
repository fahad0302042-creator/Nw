import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../core/theme_controller.dart';
import '../browse/extensions_page.dart';
import '../categories/categories_page.dart';
import '../downloads/downloads_page.dart';
import '../track/tracking_page.dart';
import 'backup_page.dart';
import 'appearance_page.dart';
import 'network_page.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final manager = ref.watch(extensionManagerProvider);
    final appearance = ref.watch(appearanceProvider);
    final downloads = ref.watch(downloadManagerProvider);
    final tracking = ref.watch(trackingServiceProvider);
    final categories = ref.watch(categoriesProvider).valueOrNull ?? const [];

    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 90),
        children: [
          _label(context, 'SOURCES'),
          _tile(
            context,
            icon: Icons.extension_outlined,
            title: 'Extensions',
            subtitle: '${manager.installed.length} installed'
                '${manager.updates.isNotEmpty ? ' · ${manager.updates.length} update(s)' : ''}',
            page: const ExtensionsPage(),
          ),
          const Hairline(indent: 16),
          _tile(
            context,
            icon: Icons.dns_outlined,
            title: 'Repositories',
            subtitle: '${manager.repoUrls.length} configured',
            page: const ReposPage(),
          ),
          const Hairline(indent: 16),
          _tile(
            context,
            icon: Icons.download_outlined,
            title: 'Downloads',
            subtitle: downloads.activeCount > 0
                ? '${downloads.activeCount} in queue'
                : '${downloads.tasks.length} saved',
            page: const DownloadsPage(),
          ),
          const Hairline(),
          _label(context, 'LIBRARY'),
          _tile(
            context,
            icon: Icons.label_outline,
            title: 'Categories',
            subtitle: categories.isEmpty
                ? 'None yet'
                : categories.map((c) => c.name).take(3).join(', '),
            page: const CategoriesPage(),
          ),
          const Hairline(indent: 16),
          _tile(
            context,
            icon: Icons.sync_alt,
            title: 'Tracking',
            subtitle: tracking.anyLoggedIn
                ? tracking.loggedIn.map((t) => t.name).join(', ')
                : 'AniList, MyAnimeList — not signed in',
            page: const TrackingPage(),
          ),
          const Hairline(indent: 16),
          _tile(
            context,
            icon: Icons.settings_backup_restore,
            title: 'Backup & restore',
            subtitle: 'Export or import your library',
            page: const BackupPage(),
          ),
          const Hairline(),
          _label(context, 'APP'),
          _tile(
            context,
            icon: Icons.palette_outlined,
            title: 'Appearance',
            subtitle: appearance.palette.label,
            page: const AppearancePage(),
          ),
          const Hairline(indent: 16),
          _tile(
            context,
            icon: Icons.shield_outlined,
            title: 'Network & browser',
            subtitle: 'Cloudflare, cookies, WebView data',
            page: const NetworkPage(),
          ),
          const Hairline(),
          _label(context, 'ABOUT'),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text(
              'Kurayomi 0.3.0\n\n'
              'A manga and anime reader with a JavaScript extension runtime. '
              'Ships with no sources and makes no requests until you add a '
              'repository yourself.',
              style: TextStyle(fontSize: 13, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 22, 16, 10),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall),
      );

  Widget _tile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget page,
  }) =>
      ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right, size: 20),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => page),
        ),
      );
}
