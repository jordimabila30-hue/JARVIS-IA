// Messages enrichis (session GH, opt. 51-53) : code et tableaux fidèles,
// défilement horizontal dans la carte, copie exacte.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ia_jarvis/services/conversation/moteur_conversation_ia.dart';
import 'package:ia_jarvis/theme/theme_jarvis.dart';
import 'package:ia_jarvis/widgets/conversation/texte_riche.dart';

const _python = '''class Point:
    def __init__(self, x):
        self.x = x ** 2  # `carré`
        print(f"{x}\\t|fin|")''';

final _reponse =
    'Voici le **code** demandé :\n\n```python\n$_python\n```\n\n'
    '| Nom | Rôle | Description très longue |\n'
    '|---|:---:|---|\n'
    '| Léa | Cheffe | ${'texte long ' * 30}|\n'
    '| Max | a \\| b |\n\n'
    'Fin du message.';

void main() {
  test('texteSimple : le code reste exact, le reste perd ses marques', () {
    final t = MoteurConversationIA.texteSimple(_reponse);
    expect(t, contains('Voici le code demandé'));
    expect(t, contains(_python));
  });

  test('texteSimpleProvisoire : un bloc de code ouvert s’écrit tel quel', () {
    final t = MoteurConversationIA.texteSimpleProvisoire(
      'Exemple :\n```dart\nfinal a = b * c;\nfinal d = `x',
    );
    expect(t, endsWith('final a = b * c;\nfinal d = `x'));
  });

  test('découpage : paragraphes, code, tableau complété', () {
    final blocs = TexteRiche.decouper(
      MoteurConversationIA.texteSimple(_reponse),
    );
    expect(blocs.map((b) => b.runtimeType), [
      Paragraphe,
      BlocCode,
      Tableau,
      Paragraphe,
    ]);
    final code = blocs[1] as BlocCode;
    expect(code.langage, 'python');
    expect(code.code, _python);
    final tableau = blocs[2] as Tableau;
    expect(tableau.lignes, hasLength(3));
    expect(tableau.lignes.first, ['Nom', 'Rôle', 'Description très longue']);
    expect(tableau.lignes.last, ['Max', 'a | b', '']);
  });

  test('utile : seulement code ou vrai tableau', () {
    expect(TexteRiche.utile('Bonjour, rien de spécial.'), isFalse);
    expect(TexteRiche.utile('Prix | quantité'), isFalse);
    expect(TexteRiche.utile(_reponse), isTrue);
  });

  for (final largeur in [320.0, 1200.0]) {
    testWidgets('largeur $largeur : rien ne déborde, copie exacte du code', (
      tester,
    ) async {
      String? copie;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (appel) async {
          if (appel.method == 'Clipboard.setData') {
            copie = (appel.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      tester.view.physicalSize = Size(largeur, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: themeJarvis(),
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: TexteRiche(
                texte: MoteurConversationIA.texteSimple(_reponse),
                style: const TextStyle(fontSize: 15),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      // Le tableau et le code tiennent dans la largeur de l'écran (ils
      // défilent à l'intérieur).
      for (final type in [Table, Text]) {
        for (final e in find.byType(type).evaluate()) {
          final r = tester.getRect(find.byWidget(e.widget));
          expect(r.left, greaterThanOrEqualTo(0));
        }
      }
      expect(
        tester.getSize(find.byType(TexteRiche)).width,
        lessThanOrEqualTo(largeur),
      );
      await tester.tap(find.byTooltip('Copier le code'));
      await tester.pump();
      expect(copie, _python);
      expect(find.byTooltip('Code copié'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      expect(find.byTooltip('Copier le code'), findsOneWidget);
    });
  }

  testWidgets('liens : destination exacte, ponctuation exclue, schémas sûrs', (
    tester,
  ) async {
    final ouverts = <Uri>[];
    final avant = TexteRiche.ouvrir;
    TexteRiche.ouvrir = (u) async {
      ouverts.add(u);
      return true;
    };
    addTearDown(() => TexteRiche.ouvrir = avant);
    const url = 'https://exemple.fr/a%20b/recherche?q=caf%C3%A9&p=2#haut';
    const texte =
        'Voir $url. Ou [la doc](https://docs.exemple.fr/x_(y)) '
        'et javascript:alert(1) ou file:///c/secret.';
    expect(TexteRiche.utile(texte), isTrue);
    expect(TexteRiche.destination('javascript:alert(1)'), isNull);
    expect(TexteRiche.destination('file:///c/secret'), isNull);
    expect(TexteRiche.destination('https://'), isNull);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 220,
            child: TexteRiche(texte: texte, style: const TextStyle()),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    final riche = tester.widget<RichText>(find.byType(RichText).first);
    final liens = <TextSpan>[];
    riche.text.visitChildren((s) {
      if (s is TextSpan && s.recognizer != null) liens.add(s);
      return true;
    });
    expect(liens.map((s) => s.text), [url, 'la doc']);
    for (final l in liens) {
      (l.recognizer! as TapGestureRecognizer).onTap!();
    }
    expect(ouverts.map((u) => u.toString()), [
      url,
      'https://docs.exemple.fr/x_(y)',
    ]);
    // Le texte affiché garde tout, liens compris.
    expect(riche.text.toPlainText(), contains(url));
    expect(riche.text.toPlainText(), contains('javascript:alert(1)'));
  });
}
