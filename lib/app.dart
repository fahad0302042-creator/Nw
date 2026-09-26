import 'package:flutter/material.dart';

import 'data/app_state.dart';
import 'ui/home_shell.dart';

/// Exposes [AppState] to the widget tree and rebuilds listeners on change.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
      : super(notifier: state);

  static AppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope was not found in the widget tree');
    return scope!.notifier!;
  }

  /// Reads the state without subscribing to rebuilds.
  static AppState read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope was not found in the widget tree');
    return scope!.notifier!;
  }
}

class KuroyomiApp extends StatelessWidget {
  const KuroyomiApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF7C5CFF),
      brightness: Brightness.dark,
    );
    return AppScope(
      state: state,
      child: MaterialApp(
        title: 'Kuroyomi',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: scheme,
          scaffoldBackgroundColor: const Color(0xFF0E0E13),
          cardTheme: const CardThemeData(
            clipBehavior: Clip.antiAlias,
            margin: EdgeInsets.zero,
          ),
          inputDecorationTheme: const InputDecorationTheme(
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        home: const HomeShell(),
      ),
    );
  }
}
