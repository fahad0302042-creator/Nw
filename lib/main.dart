import 'package:flutter/material.dart';

import 'app.dart';
import 'data/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState();
  await state.init();
  runApp(KuroyomiApp(state: state));
}
