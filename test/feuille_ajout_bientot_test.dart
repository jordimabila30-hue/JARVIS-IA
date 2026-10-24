import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ia_jarvis/widgets/feuille_ajout.dart';

void main() {
  testWidgets('Instagram, Messenger et Mail : visibles, sans action', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: FeuilleAjout())),
    );
    for (final titre in ['Instagram', 'Messenger', 'Mail']) {
      expect(find.text(titre), findsOneWidget);
    }
    expect(find.text('Bientôt disponible'), findsNWidgets(3));
    await tester.tap(find.text('Instagram'));
    await tester.pump();
    expect(find.byType(FeuilleAjout), findsOneWidget); // rien ne se passe
  });
}
