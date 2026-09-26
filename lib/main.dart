import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'app.dart';
import 'core/providers.dart';
import 'data/db/app_database.dart';
import 'data/net/app_http_client.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  final db = await AppDatabase.open();
  // Initialise early so sync call-sites (image headers) can read cookies.
  await AppHttpClient.instance();

  runApp(
    ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: const KurayomiApp(),
    ),
  );
}
