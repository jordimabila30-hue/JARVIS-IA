// Kelasi phase 2, interface : test de niveau facultatif, quatre actions du
// professeur, situations du quotidien, oral indisponible expliqué.
// Corpus réel (assets), tuteur factice (aucun réseau), stockage en mémoire.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ia_jarvis/models/apprentissage/exercice.dart';
import 'package:ia_jarvis/models/apprentissage/progression.dart';
import 'package:ia_jarvis/models/apprentissage/tuteur.dart';
import 'package:ia_jarvis/pages/apprentissage/apprendre_page.dart';
import 'package:ia_jarvis/pages/apprentissage/lecon_page.dart';
import 'package:ia_jarvis/services/api_jarvis.dart';
import 'package:ia_jarvis/services/apprentissage/catalogue_apprentissage.dart';
import 'package:ia_jarvis/services/apprentissage/espace_apprentissage.dart';
import 'package:ia_jarvis/services/apprentissage/service_progression.dart';
import 'package:ia_jarvis/services/apprentissage/session_tuteur.dart';
import 'package:ia_jarvis/services/voice_settings_service.dart';
import 'package:ia_jarvis/theme/theme_jarvis.dart';

/// Tuteur factice : répond en deux fragments, sources validées.
class _Tuteur {
  final demandes = <DemandeTuteur>[];

  Future<ResultatApi<ReponseTuteur>> call(
    DemandeTuteur d, {
    Future<void>? annulation,
    void Function(String fragment)? surFragment,
  }) async {
    demandes.add(d);
    surFragment?.call('Règle : dites « Madame, ».\n');
    await Future<void>.delayed(const Duration(milliseconds: 10));
    surFragment?.call('Exemple : Madame, je vous écris…');
    return const SuccesApi(
      ReponseTuteur(
        texte: 'Règle : dites « Madame, ».\nExemple : Madame, je vous écris…',
        sources: [
          SourceTuteur(
            fiche: 'cor-f-appel',
            titre: 'S’adresser à la personne',
            validee: false,
            references: [(titre: 'BDL', editeur: 'OQLF', url: null)],
          ),
        ],
      ),
    );
  }
}

EspaceApprentissage _espace({AppelTuteur? tuteur}) => EspaceApprentissage(
  catalogue: CatalogueApprentissage(apercu: true),
  progression: ServiceProgression(
    principal: StockageMemoire(),
    secours: StockageMemoire(),
    corrompue: StockageMemoire(),
  ),
  tuteur: tuteur,
);

Future<void> _ouvrir(WidgetTester tester, EspaceApprentissage espace) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: themeJarvis(),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => ouvrirApprendre(context, espace),
            child: const Text('JARVIS'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('JARVIS'));
  await tester.pumpAndSettle();
}

Future<void> _fin(WidgetTester tester, EspaceApprentissage espace) async {
  await tester.pumpWidget(const SizedBox());
  espace.dispose();
  await tester.pump(const Duration(seconds: 2));
}

Future<void> _toucher(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Finder _cle(String c) => find.byKey(ValueKey(c));

Future<void> _repondreJuste(WidgetTester tester, Exercice e) async {
  switch (e) {
    case ExerciceChoix():
      await _toucher(tester, _cle('option-${e.bonne}'));
    case ExerciceVraiFaux():
      await _toucher(tester, _cle(e.reponse ? 'vrai' : 'faux'));
    case ExerciceTrous():
      for (var i = 0; i < e.trous.length; i++) {
        await _toucher(tester, _cle('trou-$i'));
        await _toucher(tester, _cle('mot-${e.trous[i].bonne}'));
      }
      await _toucher(tester, find.text('Vérifier'));
    case ExerciceOrdre():
      for (var i = 0; i < e.elements.length; i++) {
        await _toucher(tester, _cle('element-$i'));
      }
      await _toucher(tester, find.text('Vérifier'));
    case ExerciceAssociation():
      for (var g = 0; g < e.paires.length; g++) {
        await _toucher(tester, _cle('gauche-$g'));
        await _toucher(tester, _cle('droite-$g'));
      }
      await _toucher(tester, find.text('Vérifier'));
  }
}

void main() {
  testWidgets('test de niveau facultatif : proposé, passable, puis estimé', (
    tester,
  ) async {
    final espace = _espace();
    await _ouvrir(tester, espace);
    await _toucher(tester, _cle('parcours-technique'));
    expect(find.text('Découvrir mon niveau'), findsOneWidget);
    // Commencer directement : jamais imposé, toujours accessible.
    await _toucher(tester, _cle('passer-test'));
    expect(find.text('Découvrir mon niveau'), findsNothing);
    expect(find.text('Niveau non évalué'), findsOneWidget);
    await _toucher(tester, _cle('refaire-test'));
    expect(find.byType(LeconPage), findsOneWidget);
    // Toutes les réponses justes → Avancé.
    final l = espace.catalogue.parcoursDe('technique')!.leconsVisibles(apercu: true);
    final total = l.expand((x) => x.exercices).length.clamp(0, 5);
    for (var i = 0; i < total; i++) {
      final e = espace.catalogue.parcoursDe('technique')!.contenu!.lecons
          .expand((x) => x.exercices)
          .firstWhere((x) => find.text(x.consigne).evaluate().isNotEmpty);
      await _repondreJuste(tester, e);
      await _toucher(tester, _cle('continuer'));
    }
    expect(find.text('Test terminé'), findsOneWidget);
    expect(find.text('Niveau estimé : Avancé'), findsOneWidget);
    expect(espace.progression.niveau('technique'), NiveauApprenant.avance);
    await _toucher(tester, _cle('resultat-continuer'));
    expect(find.text('Niveau : Avancé'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _fin(tester, espace);
  });

  testWidgets('quatre actions : « Mon erreur » envoie l’exercice et la réponse, '
      'réponse en direct, sources validées à la fin', (tester) async {
    final tuteur = _Tuteur();
    final espace = _espace(tuteur: tuteur.call);
    await _ouvrir(tester, espace);
    await _toucher(tester, _cle('parcours-correspondance'));
    await _toucher(tester, _cle('passer-test'));
    await _toucher(tester, _cle('lecon-cor-l1'));
    // Introduction : Plus simplement / Un exemple / M'entraîner par fiche.
    expect(_cle('tuteur-simplifier'), findsWidgets);
    expect(_cle('tuteur-erreur'), findsNothing);
    await _toucher(tester, _cle('commencer'));
    await _toucher(tester, _cle('option-0')); // « Salut ! » : faux
    expect(_cle('tuteur-erreur'), findsOneWidget);
    await _toucher(tester, _cle('tuteur-erreur'));
    final d = tuteur.demandes.single;
    expect(d.action, ActionTuteur.erreur);
    expect(d.exercice, 'cor-l1-e1');
    expect(d.reponse, 'Salut !');
    expect(d.fiches, ['cor-f-appel']);
    expect(d.versionCorpus, espace.catalogue.versionCorpus);
    expect(find.textContaining('dites « Madame, »'), findsOneWidget);
    expect(find.text('Fiches utilisées'), findsOneWidget);
    expect(find.text('S’adresser à la personne'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _fin(tester, espace);
  });

  testWidgets('sans compte : le professeur IA explique la connexion, les '
      'leçons restent disponibles', (tester) async {
    final espace = _espace();
    await _ouvrir(tester, espace);
    await _toucher(tester, _cle('parcours-correspondance'));
    await _toucher(tester, _cle('passer-test'));
    await _toucher(tester, _cle('lecon-cor-l1'));
    await _toucher(tester, _cle('tuteur-exemple').first);
    expect(find.text(SessionTuteur.sansCompte), findsOneWidget);
    expect(_cle('tuteur-reessayer'), findsNothing);
    await _fin(tester, espace);
  });

  testWidgets('M’entraîner : exercices locaux de la même notion, sans IA', (
    tester,
  ) async {
    final tuteur = _Tuteur();
    final espace = _espace(tuteur: tuteur.call);
    await _ouvrir(tester, espace);
    await _toucher(tester, _cle('parcours-correspondance'));
    await _toucher(tester, _cle('passer-test'));
    await _toucher(tester, _cle('lecon-cor-l1'));
    await _toucher(tester, _cle('tuteur-entrainer').last);
    // Une séance libre s'ouvre par-dessus la leçon : cor-f-corps a 4
    // exercices locaux.
    expect(find.byType(LeconPage, skipOffstage: false), findsNWidgets(2));
    expect(find.text('0 / 4'), findsOneWidget);
    expect(tuteur.demandes, isEmpty);
    await _fin(tester, espace);
  });

  testWidgets('situations : liste, correction écrite, nouvelle tentative ; '
      'oral expliqué quand il est indisponible', (tester) async {
    final tuteur = _Tuteur();
    final espace = _espace(tuteur: tuteur.call);
    await _ouvrir(tester, espace);
    expect(_cle('liste-situations'), findsOneWidget);
    await _toucher(tester, _cle('situation-sit-professeur'));
    expect(find.text('Demander un délai pour un devoir, poliment et clairement.'), findsOneWidget);
    // Sans voix (tests) : oral désactivé, raison affichée.
    expect(_cle('situation-oral-raison'), findsOneWidget);
    await tester.enterText(_cle('situation-saisie'), 'Bonjour, je voudrais un délai.');
    await tester.pump();
    await _toucher(tester, _cle('situation-corriger'));
    expect(tuteur.demandes.single.action, ActionTuteur.situation);
    expect(tuteur.demandes.single.situation, 'sit-professeur');
    expect(tuteur.demandes.single.texte, 'Bonjour, je voudrais un délai.');
    expect(find.textContaining('dites « Madame, »'), findsOneWidget);
    await _toucher(tester, _cle('situation-nouvelle'));
    expect(_cle('situation-corriger'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _fin(tester, espace);
  });

  testWidgets('hors aperçu (release) : aucune situation en brouillon', (
    tester,
  ) async {
    final espace = EspaceApprentissage(
      catalogue: CatalogueApprentissage(apercu: false, release: true),
      progression: ServiceProgression(
        principal: StockageMemoire(),
        secours: StockageMemoire(),
        corrompue: StockageMemoire(),
      ),
    );
    await _ouvrir(tester, espace);
    expect(_cle('liste-situations'), findsNothing);
    expect(espace.catalogue.situations, isEmpty);
    await _fin(tester, espace);
  });
}
