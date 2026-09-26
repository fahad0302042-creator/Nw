import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsundoku/ui/widgets/state_views.dart';

void main() {
  testWidgets('EmptyState renders title and message', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: EmptyState(
            icon: Icons.inbox_outlined,
            title: 'Nothing here',
            message: 'Try adding something',
          ),
        ),
      ),
    );

    expect(find.text('Nothing here'), findsOneWidget);
    expect(find.text('Try adding something'), findsOneWidget);
    expect(find.byIcon(Icons.inbox_outlined), findsOneWidget);
  });
}
