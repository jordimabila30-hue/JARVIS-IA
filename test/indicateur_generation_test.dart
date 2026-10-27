import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ia_jarvis/models/message_conversation.dart';
import 'package:ia_jarvis/services/ecriture/ecriture_progressive.dart';
import 'package:ia_jarvis/services/ecriture/texte_en_direct.dart';
import 'package:ia_jarvis/widgets/conversation/carte_jarvis.dart';
import 'package:ia_jarvis/widgets/conversation/indicateur_generation.dart';

Widget _app(Widget w, {bool reduire = false}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduire),
    child: Scaffold(body: SingleChildScrollView(child: w)),
  ),
);

MessageConversation _reponse({
  required bool redaction,
  String texte = 'Bonjour.',
}) {
  final flux = TexteEnDirect()..terminer(texte);
  return MessageConversation(
    id: 1,
    auteur: AuteurMessage.jarvis,
    heure: DateTime(2026, 10, 27, 10),
    texte: texte,
    redaction: redaction,
    ecriture: EcritureProgressive(flux)..toutAfficher(),
  );
}

CarteJarvis _carte(MessageConversation m) =>
    CarteJarvis(message: m, surTon: (_) {}, surAction: (_) {});

void main() {
  testWidgets('A. préparation : cercle + « Préparation… » ; libellé long après '
      'une attente anormale', (t) async {
    await t.pumpWidget(_app(const ReflexionJarvis()));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text(IndicateurGeneration.preparation), findsOneWidget);
    await t.pump(const Duration(seconds: 16));
    expect(find.text(IndicateurGeneration.longue), findsOneWidget);
  });

  testWidgets('B. réception : « Rédaction… » ; D. fin : plus aucun indicateur, '
      'même hauteur', (t) async {
    await t.pumpWidget(_app(_carte(_reponse(redaction: true))));
    expect(find.text(IndicateurGeneration.redaction), findsOneWidget);
    final pendant = t.getSize(find.byType(CarteJarvis)).height;
    await t.pumpWidget(_app(_carte(_reponse(redaction: false))));
    await t.pump();
    expect(find.byKey(const Key('indicateur-generation')), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(t.getSize(find.byType(CarteJarvis)).height, pendant); // aucun saut
  });

  testWidgets('animations réduites : point fixe, aucune animation', (t) async {
    await t.pumpWidget(_app(const ReflexionJarvis(), reduire: true));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text(IndicateurGeneration.preparation), findsOneWidget);
  });

  testWidgets('réveil du serveur : libellé réel', (t) async {
    final reveil = ValueNotifier(true);
    await t.pumpWidget(_app(ReflexionJarvis(reveilServeur: reveil)));
    expect(find.text(ReflexionJarvis.connexion), findsOneWidget);
    reveil.value = false;
    await t.pump();
    expect(find.text(IndicateurGeneration.preparation), findsOneWidget);
  });
}
