import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ia_jarvis/pages/ecran_de_lancement.dart';
import 'package:ia_jarvis/theme/theme_jarvis.dart';

Widget _app(VoidCallback surFin) => MaterialApp(
  theme: themeJarvis(),
  home: EcranDeLancement(onTermine: surFin),
);

void main() {
  testWidgets('sans appui : la suite vient à la fin de l’animation, une fois', (
    t,
  ) async {
    var fins = 0;
    await t.pumpWidget(_app(() => fins++));
    await t.pump(const Duration(milliseconds: 1000));
    expect(fins, 0);
    await t.pump(const Duration(milliseconds: 2300));
    expect(fins, 1);
    await t.pump(const Duration(seconds: 2));
    expect(fins, 1);
  });

  testWidgets('un appui passe l’animation, jamais deux suites', (t) async {
    var fins = 0;
    await t.pumpWidget(_app(() => fins++));
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.byType(EcranDeLancement));
    expect(fins, 1);
    await t.tap(find.byType(EcranDeLancement));
    // La fin naturelle de l'animation ne relance pas la suite.
    await t.pump(const Duration(seconds: 4));
    expect(fins, 1);
  });
}
