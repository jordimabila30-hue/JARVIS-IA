import 'package:flutter_test/flutter_test.dart';
import 'package:ia_jarvis/widgets/conversation/carte_jarvis.dart';
import 'package:ia_jarvis/widgets/ecriture/texte_progressif.dart';

/// Les réponses de JARVIS s'écrivent progressivement (phase 4) : avance
/// image par image tant que JARVIS réfléchit ou qu'une réponse est encore
/// en train de s'écrire (curseur d'écriture visible), au plus [max].
Future<void> finirEcritures(
  WidgetTester tester, {
  Duration max = const Duration(seconds: 30),
}) async {
  const image = Duration(milliseconds: 16);
  bool enCours() =>
      find.byType(ReflexionJarvis).evaluate().isNotEmpty ||
      find.byKey(TexteProgressif.cleCurseur).evaluate().isNotEmpty;
  var t = Duration.zero;
  while (enCours() && t < max) {
    await tester.pump(image);
    t += image;
  }
  // Les éléments qui apparaissent en fin d'écriture (raccourcis, choix du
  // ton) ont une image pour se poser.
  await tester.pump(image);
}
