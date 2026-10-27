import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ia_jarvis/widgets/conversation/selecteurs_reponse.dart';

Widget _cadre(Widget w, {double largeur = 360, double texte = 1}) =>
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(texte)),
        child: Scaffold(
          body: Center(
            child: SizedBox(width: largeur, child: w),
          ),
        ),
      ),
    );

void main() {
  int ton = 0, longueur = 1;
  SelecteursReponse s() => SelecteursReponse(
    tons: const ['Tendre', 'Neutre', 'Professionnel'],
    ton: ton,
    surTon: (i) => ton = i,
    longueurs: const ['Court', 'Moyen', 'Long'],
    longueur: longueur,
    surLongueur: (i) => longueur = i,
  );

  testWidgets('côte à côte, même hauteur, valeurs visibles', (t) async {
    await t.pumpWidget(_cadre(s()));
    final a = t.getRect(find.byKey(SelecteursReponse.cleTon));
    final b = t.getRect(find.byKey(SelecteursReponse.cleLongueur));
    expect(a.top, b.top);
    expect(a.height, b.height);
    expect(a.width, moreOrLessEquals(b.width, epsilon: 1));
    expect(a.height, greaterThanOrEqualTo(44)); // zone tactile confortable
    expect(find.text('Tendre'), findsOneWidget);
    expect(find.text('Moyen'), findsOneWidget);
  });

  testWidgets('choix : tous les tons existants, sélection remontée', (t) async {
    await t.pumpWidget(_cadre(s()));
    await t.tap(find.byKey(SelecteursReponse.cleTon));
    await t.pumpAndSettle();
    for (final n in ['Tendre', 'Neutre', 'Professionnel']) {
      expect(find.byKey(SelecteursReponse.choixTon(n)), findsOneWidget);
    }
    await t.tap(find.byKey(SelecteursReponse.choixTon('Professionnel')));
    await t.pumpAndSettle();
    expect(ton, 2);
    await t.tap(find.byKey(SelecteursReponse.cleLongueur));
    await t.pumpAndSettle();
    await t.tap(find.byKey(SelecteursReponse.choixLongueur('long')));
    await t.pumpAndSettle();
    expect(longueur, 2);
  });

  for (final (largeur, texte) in [(200.0, 1.0), (360.0, 2.0)]) {
    testWidgets('écran $largeur px, texte ×$texte : l’un sous l’autre, sans '
        'débordement', (t) async {
      ton = 0;
      longueur = 1;
      await t.pumpWidget(_cadre(s(), largeur: largeur, texte: texte));
      expect(t.takeException(), isNull);
      final a = t.getRect(find.byKey(SelecteursReponse.cleTon));
      final b = t.getRect(find.byKey(SelecteursReponse.cleLongueur));
      expect(b.top, greaterThan(a.bottom - 1));
    });
  }

  testWidgets('sans longueurs : un seul menu', (t) async {
    await t.pumpWidget(
      _cadre(
        SelecteursReponse(tons: const ['Naturel'], ton: 0, surTon: (_) {}),
      ),
    );
    expect(find.byKey(SelecteursReponse.cleLongueur), findsNothing);
  });
}
