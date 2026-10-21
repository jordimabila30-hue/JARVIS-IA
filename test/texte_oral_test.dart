import 'package:flutter_test/flutter_test.dart';
import 'package:ia_jarvis/services/texte_oral.dart';

void main() {
  String oral(String t) => TexteOral.preparer(t);

  test('liste numérotée : enchaînement parlé, plus de numéros ni de « : »', () {
    final t = oral(
      'La photosynthèse comprend trois étapes :\n'
      '1. Absorption de la lumière.\n'
      '2. Transformation de l’énergie.\n'
      '3. Production de sucres et libération d’oxygène.',
    );
    expect(
      t,
      'La photosynthèse comprend trois étapes. D’abord, absorption de la '
      'lumière. Ensuite, transformation de l’énergie. Enfin, production de '
      'sucres et libération d’oxygène.',
    );
  });

  test('Markdown jamais prononcé', () {
    final t = oral(
      '## Résumé\n**Important** : *vraiment* ~~pas~~ `code` [lien](https://x.fr)\n---\n> Citation',
    );
    expect(t, isNot(contains(RegExp(r'[*#`~>\[\]]'))));
    expect(t, 'Résumé. Important : vraiment pas code lien. Citation.');
  });

  test('puces : des phrases', () {
    expect(oral('- pommes\n- poires\n* ADN'), 'pommes. poires. ADN.');
  });

  test('chiffres, dates, pourcentages intacts ; unités dites en mots', () {
    final t = oral('Le 14 juillet 1789, 42,5 % des votes ; 90 km/h et 25°C sur 3 m².');
    expect(t, contains('14 juillet 1789'));
    expect(t, contains('42,5 %'));
    expect(t, contains('90 kilomètres par heure'));
    expect(t, contains('25 degrés Celsius'));
    expect(t, contains('3 mètres carrés'));
  });

  test('symboles mathématiques, flèches, émojis', () {
    expect(oral('a ≈ 3 → b ≠ c 🙂'), 'a environ 3, puis b différent de c.');
    expect(oral('2 × 3 = 6'), '2 fois 3 = 6.');
  });

  test('tableau et code : jamais lus symbole par symbole', () {
    final t = oral('| Nom | Âge |\n|---|---|\n| Tony | 48 |\n```dart\nvoid main() {}\n```');
    expect(t, 'Nom, Âge. Tony, 48. Le code est affiché à l’écran.');
  });

  test('réponse courte inchangée', () {
    expect(oral('Il est 14 h 05.'), 'Il est 14 h 05.');
  });

  test('code au milieu d’une phrase : la phrase reste entière', () {
    expect(
      oral('Utilise `print()` puis ```dart\nvoid main() {}\n``` ensuite.'),
      'Utilise print puis (le code est affiché à l’écran) ensuite.',
    );
    expect(
      oral('Voici :\n```\nx = 1\n```\nC’est tout.'),
      'Voici : Le code est affiché à l’écran. C’est tout.',
    );
  });

  test('« ~ » devant un nombre : environ', () {
    expect(oral('Comptez ~ 5 minutes.'), 'Comptez environ 5 minutes.');
  });
}
