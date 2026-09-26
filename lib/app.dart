import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/app_keys.dart';
import 'core/providers.dart';
import 'core/theme.dart';
import 'core/theme_controller.dart';
import 'data/notify/notification_service.dart';
import 'features/browse/browse_page.dart';
import 'features/library/history_page.dart';
import 'features/library/library_page.dart';
import 'features/settings/settings_page.dart';

class KurayomiApp extends ConsumerStatefulWidget {
  const KurayomiApp({super.key});
  @override
  ConsumerState<KurayomiApp> createState() => _KurayomiAppState();
}

class _KurayomiAppState extends ConsumerState<KurayomiApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(extensionManagerProvider).init();
      // Resumes anything left queued by a previous run.
      ref.read(downloadManagerProvider).init();
      // Android 13+ needs this before library-update notifications appear.
      NotificationService.instance.requestPermission();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeDataProvider);

    return MaterialApp(
      title: 'Kurayomi',
      debugShowCheckedModeBanner: false,
      // The HTTP layer pushes the Cloudflare challenge screen through this.
      navigatorKey: rootNavigatorKey,
      theme: theme,
      home: const RootShell(),
    );
  }
}

class RootShell extends StatefulWidget {
  const RootShell({super.key});
  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;

  static const _pages = [
    LibraryPage(),
    BrowsePage(),
    HistoryPage(),
    SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // extendBody + a frosted bar lets covers scroll under the nav,
      // the way iOS tab bars behave.
      extendBody: true,
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: FrostedBar(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Hairline(),
            NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.book_outlined),
                  selectedIcon: Icon(Icons.book),
                  label: 'Library',
                ),
                NavigationDestination(
                  icon: Icon(Icons.explore_outlined),
                  selectedIcon: Icon(Icons.explore),
                  label: 'Browse',
                ),
                NavigationDestination(
                  icon: Icon(Icons.schedule_outlined),
                  selectedIcon: Icon(Icons.schedule),
                  label: 'History',
                ),
                NavigationDestination(
                  icon: Icon(Icons.more_horiz),
                  selectedIcon: Icon(Icons.more_horiz),
                  label: 'More',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
