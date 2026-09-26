import 'package:flutter/material.dart';

import 'ui/home/main_shell.dart';

class TsundokuApp extends StatelessWidget {
  const TsundokuApp({super.key});

  @override
  Widget build(BuildContext context) {
    final seed = const Color(0xFFE8623C);
    return MaterialApp(
      title: 'Tsundoku',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seed),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const MainShell(),
    );
  }
}
