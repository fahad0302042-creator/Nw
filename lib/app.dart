import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/providers.dart';
import 'core/theme.dart';
import 'features/browse/browse_page.dart';
import 'features/library/library_page.dart';
import 'features/settings/settings_page.dart';
import 'features/library/history_page.dart';

class KurayomiApp extends ConsumerStatefulWidget {
  const KurayomiApp({super.key});
  @override
  ConsumerState<KurayomiApp> createState() => _KurayomiAppState();
}

class _KurayomiAppState extends ConsumerState<KurayomiApp> {
  @override
  void initState() {
    super.initState();
    // Load installed extensions in the background; the UI is usable meanwhile.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(extensionManagerProvider).init();
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kurayomi',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
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
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.collections_bookmark_outlined),
            selectedIcon: Icon(Icons.collections_bookmark),
            label: 'Library',
          ),
          NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore),
            label: 'Browse',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history),
            label: 'History',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'More',
          ),
        ],
      ),
    );
  }
}
