import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuroyomi/app.dart';
import 'package:kuroyomi/data/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('app boots into an empty library', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final state = AppState();
    await state.init();

    await tester.pumpWidget(KuroyomiApp(state: state));
    await tester.pump();

    expect(find.text('Library'), findsWidgets);
    expect(find.text('Your library is empty'), findsOneWidget);
  });

  testWidgets('navigating to Extensions shows the repository field',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final state = AppState();
    await state.init();

    await tester.pumpWidget(KuroyomiApp(state: state));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.extension_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Extension repository url'), findsOneWidget);
    expect(find.text('Load demo repository'), findsOneWidget);
  });
}
