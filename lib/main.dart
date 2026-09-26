import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/source/source_manager.dart';
import 'core/storage/app_storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final storage = AppStorage.instance;
  await storage.init();

  final sourceManager = SourceManager(storage);
  await sourceManager.loadInstalled();
  await sourceManager.seedBundledExtensionsIfFirstRun();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppStorage>.value(value: storage),
        ChangeNotifierProvider<SourceManager>.value(value: sourceManager),
      ],
      child: const TsundokuApp(),
    ),
  );
}
