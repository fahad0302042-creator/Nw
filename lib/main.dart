import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'app.dart';
import 'core/providers.dart';
import 'data/db/app_database.dart';
import 'data/net/app_http_client.dart';
import 'data/notify/notification_service.dart';
import 'data/track/token_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  final db = await AppDatabase.open();
  // Initialise early so sync call-sites (image headers) can read cookies.
  await AppHttpClient.instance();
  final tokens = await TokenStore.instance();
  await NotificationService.instance.init();

  runApp(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        tokenStoreProvider.overrideWithValue(tokens),
      ],
      child: const KurayomiApp(),
    ),
  );
}
