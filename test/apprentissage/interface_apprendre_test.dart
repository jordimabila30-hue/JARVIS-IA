// Module Apprendre : interface (accueil, parcours, leçon, résultat),
// progression réelle des barres, reprise, hors aperçu, écoute sans voix,
// tailles d'écran et thèmes. Corpus réel des assets, stockage en mémoire.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ia_jarvis/models/apprentissage/exercice.dart';
import 'package:ia_jarvis/pages/apprentissage/apprendre_page.dart';
import 'package:ia_jarvis/pages/apprentissage/lecon_page.dart';
import 'package:ia_jarvis/pages/apprentissage/parcours_page.dart';
import 'package:ia_jarvis/services/apprentissage/catalogue_apprentissage.dart';
import 'package:ia_jarvis/services/apprentissage/espace_apprentissage.dart';
import 'package:ia_jarvis/services/apprentissage/service_progression.dart';
import 'package:ia_jarvis/services/voice_settings_service.dart';
import 'package:ia_jarvis/theme/styles_jarvis.dart';
import 'package:ia_jarvis/theme/theme_jarvis.dart';
import 'package:ia_jarvis/widgets/apprentissage/cartes_apprendre.dart';
import 'package:ia_jarvis/widgets/apprentissage/elements_apprentissage.dart';
import 'package:ia_jarvis/widgets/apprentissage/exercices/vue_exercice.dart';

late StockageMemoire _stockage;

EspaceApprentissage _espace({bool apercu = true, LecteurEcoute? lecteur}) {
  _stockage = StockageMemoire();
  return EspaceApprentissage(
    catalogue: CatalogueApprentissage(apercu: apercu),
    progression: ServiceProgression(
      principal: _stockage,
      secours: StockageMemoire(),
      corrompue: StockageMemoire(),
    ),
    lecteur: lecteur,
  );
}

Future<void> _ouvrir(
  WidgetTester tester,
  EspaceApprentissage espace, {
  Size taille = const Size(390, 844),
  ThemeData? theme,
}) async {
  tester.view.physicalSize = taille;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? themeJarvis(),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => ouvrirApprendre(context, espace),
              child: const Text('JARVIS'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('JARVIS'));
  await tester.pumpAndSettle();
}

/// Fin de test : arbre retiré, écritures en attente terminées.
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

/// Répond juste à [e], au doigt, comme l'utilisateur.
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

Future<void> _ouvrirLecon(
  WidgetTester tester,
  String parcours,
  String lecon,
) async {
  await _toucher(tester, _cle('parcours-$parcours'));
  await _toucher(tester, _cle('lecon-$lecon'));
}

void main() {
  testWidgets('accueil : continuer, trois accès, quatre parcours avec '
      'barre et pourcentage réel', (tester) async {
    final espace = _espace();
    await _ouvrir(tester, espace);
    expect(find.text('Apprendre'), findsOneWidget);
    expect(find.text('Prêt à apprendre ?'), findsOneWidget);
    for (final a in ['Parcours', 'Pratiquer', 'Réviser']) {
      expect(find.text(a), findsOneWidget);
    }
    expect(find.byType(CarteParcours), findsNWidgets(4));
    for (final t in [
      'Correspondance',
      'Communication',
      'Relations et respect',
      'Termes techniques',
    ]) {
      expect(find.text(t), findsOneWidget);
    }
    // Barre toujours présente sur chaque carte, même à 0 %.
    for (final c in find.byType(CarteParcours).evaluate()) {
      expect(
        find.descendant(
          of: find.byWidget(c.widget),
          matching: find.byType(BarreProgression),
        ),
        findsOneWidget,
      );
    }
    expect(find.text('0 % terminé'), findsNWidgets(4));
    // Rien à réviser avant d'avoir étudié.
    expect(find.text('Rien à revoir'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _fin(tester, espace);
  });

  testWidgets('leçon complète au doigt : résultat, barres à 100 %, '
      'progression écrite', (tester) async {
    final espace = _espace();
    await _ouvrir(tester, espace);
    await _ouvrirLecon(tester, 'correspondance', 'cor-l1');
    // Introduction : objectif, fiches, sources.
    expect(
      find.text('Écrire un courriel clair et poli à un professeur.'),
      findsOneWidget,
    );
    expect(find.text('Brouillon · à valider'), findsWidgets);
    await _toucher(tester, _cle('commencer'));
    final lecon = espace.catalogue.lecon('cor-l1')!.$2;
    for (final e in lecon.exercices) {
      expect(find.text(e.consigne), findsOneWidget);
      await _repondreJuste(tester, e);
      expect(find.text('Bonne réponse'), findsOneWidget, reason: e.id);
      expect(find.text(e.explication), findsOneWidget);
      await _toucher(tester, _cle('continuer'));
    }
    expect(find.text('Leçon terminée'), findsOneWidget);
    expect(find.text('7 / 7'), findsOneWidget);
    expect(find.text('Notions acquises'), findsOneWidget);
    expect(find.text('Réviser'), findsNothing);
    // Écrite aussitôt, sans attendre le regroupement.
    expect(_stockage.valeur, contains('"terminee":true'));
    await _toucher(tester, _cle('resultat-continuer'));
    expect(find.byType(ParcoursPage), findsOneWidget);
    expect(find.text('100 %'), findsOneWidget);
    await _toucher(tester, find.byTooltip('Retour'));
    expect(find.text('100 % terminé'), findsOneWidget);
    expect(find.text('0 % terminé'), findsNWidgets(3));
    expect(tester.takeException(), isNull);
    await _fin(tester, espace);
  });

  testWidgets('réponse fausse : correction claire, réessayer, puis Réviser', (
    tester,
  ) async {
    final espace = _espace();
    await _ouvrir(tester, espace);
    await _ouvrirLecon(tester, 'correspondance', 'cor-l1');
    await _toucher(tester, _cle('commencer'));
    await _toucher(tester, _cle('option-0'));
    expect(find.text('Pas tout à fait'), findsOneWidget);
    expect(find.text('Réponse attendue'), findsOneWidget);
    expect(find.text('Source'), findsOneWidget);
    await _toucher(tester, find.text('Réessayer'));
    expect(find.text('Pas tout à fait'), findsNothing);
    await _toucher(tester, _cle('option-1'));
    expect(find.text('Bonne réponse'), findsOneWidget);
    // Noté à réviser (premier essai faux).
    expect(espace.progression.donnees.aReviser, contains('cor-l1-e1'));
    // La source s'ouvre depuis la correction.
    await _toucher(tester, find.text('Source'));
    expect(find.text('Sources'), findsOneWidget);
    expect(find.textContaining('Consultée le 20/10/2026'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await _fin(tester, espace);
  });

  testWidgets('reprise : quitter puis revenir au même exercice', (
    tester,
  ) async {
    final espace = _espace();
    await _ouvrir(tester, espace);
    await _ouvrirLecon(tester, 'relations', 'rel-l1');
    await _toucher(tester, _cle('commencer'));
    final lecon = espace.catalogue.lecon('rel-l1')!.$2;
    for (final e in lecon.exercices.take(2)) {
      await _repondreJuste(tester, e);
      await _toucher(tester, _cle('continuer'));
    }
    expect(find.text('2 / 7'), findsOneWidget);
    await _toucher(tester, find.byTooltip('Quitter (progression gardée)'));
    expect(find.text('En cours · 2 / 7'), findsOneWidget);
    await _toucher(tester, find.byTooltip('Retour'));
    expect(find.text('On continue ?'), findsOneWidget);
    await _toucher(tester, _cle('apprendre-continuer'));
    // Directement au troisième exercice, sans l'introduction.
    expect(find.text(lecon.exercices[2].consigne), findsOneWidget);
    expect(find.text('2 / 7'), findsOneWidget);
    await _fin(tester, espace);
  });

  testWidgets('hors aperçu : aucun brouillon publié, état clair', (
    tester,
  ) async {
    final espace = _espace(apercu: false);
    await _ouvrir(tester, espace);
    // Le jour où des fiches seront validées, elles seront publiées.
    final publiees = espace.catalogue.parcours!
        .expand((p) => p.leconsVisibles(apercu: false))
        .toList();
    if (publiees.isNotEmpty) {
      expect(find.text('Contenus en validation'), findsNothing);
      await _fin(tester, espace);
      return;
    }
    expect(find.text('Contenus en validation'), findsOneWidget);
    expect(find.text('En préparation'), findsNWidgets(4));
    expect(find.byType(BarreProgression), findsNWidgets(4));
    // Pratiquer indisponible : rien ne s'ouvre.
    await _toucher(tester, _cle('acces-pratiquer'));
    expect(find.byType(LeconPage), findsNothing);
    await _toucher(tester, _cle('parcours-technique'));
    expect(find.text('Leçons en cours de validation'), findsOneWidget);
    await _fin(tester, espace);
  });

  testWidgets('Pratiquer : séance de 6 exercices hors ligne', (tester) async {
    final espace = _espace();
    await _ouvrir(tester, espace);
    await _toucher(tester, _cle('acces-pratiquer'));
    expect(find.byType(LeconPage), findsOneWidget);
    expect(find.text('0 / 6'), findsOneWidget);
    await _fin(tester, espace);
  });

  testWidgets('écoute : sans voix le texte est affiché ; voix en échec, '
      'le texte apparaît', (tester) async {
    const e = ExerciceChoix(
      id: 'ec',
      fiche: 'f',
      consigne: 'Écoutez.',
      explication: '!',
      type: TypeExercice.ecoute,
      options: ['A', 'B'],
      bonne: 0,
      audio: 'Bonjour à tous.',
    );
    Widget vue(LecteurEcoute? l) => MaterialApp(
      theme: themeJarvis(),
      home: Scaffold(
        body: VueExercice(
          key: UniqueKey(),
          exercice: e,
          correction: null,
          surReponse: (_) {},
          lecteur: l,
        ),
      ),
    );
    await tester.pumpWidget(vue(null));
    expect(find.text('« Bonjour à tous. »'), findsOneWidget);
    expect(
      find.text('Lecture vocale indisponible : lisez le texte.'),
      findsOneWidget,
    );
    expect(find.text('A'), findsOneWidget);

    final lecteur = _Lecteur(reussit: false);
    await tester.pumpWidget(vue(lecteur));
    expect(find.text('« Bonjour à tous. »'), findsNothing);
    await tester.tap(_cle('ecouter'));
    await tester.pumpAndSettle();
    expect(lecteur.lus, ['Bonjour à tous.']);
    expect(find.text('« Bonjour à tous. »'), findsOneWidget);
  });

  testWidgets('texte à trous : « ? » reste collé au mot précédent', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: themeJarvis(),
        home: Scaffold(
          body: VueExercice(
            exercice: const ExerciceTrous(
              id: 't',
              fiche: 'f',
              consigne: 'Complétez.',
              explication: '!',
              texte: 'Pages à lire ? ___ salutations',
              trous: [
                Trou(options: ['Meilleures', 'Bisous'], bonne: 0),
              ],
            ),
            correction: null,
            surReponse: (_) {},
          ),
        ),
      ),
    );
    expect(find.text('lire ?'), findsOneWidget);
    expect(find.text('?'), findsNothing);
  });

  testWidgets('tailles d’écran : aucun débordement, de 320 px à l’ordinateur', (
    tester,
  ) async {
    for (final taille in const [
      Size(320, 568),
      Size(768, 1024),
      Size(1440, 900),
    ]) {
      final espace = _espace();
      await _ouvrir(tester, espace, taille: taille);
      expect(tester.takeException(), isNull, reason: '$taille accueil');
      // Exercice d'association (deux colonnes) : le plus étroit.
      await _ouvrirLecon(tester, 'technique', 'tec-l1');
      await _toucher(tester, _cle('commencer'));
      expect(find.text('Associez chaque élément à son rôle.'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: '$taille leçon');
      await _fin(tester, espace);
    }
  });

  testWidgets('thèmes : la palette active colore le module (style importé, '
      'sombre)', (tester) async {
    final avant = PaletteJarvis.active;
    addTearDown(() => PaletteJarvis.active = avant);
    final palette = StyleVisuel.values.last.palette(Brightness.dark);
    PaletteJarvis.active = palette;
    final espace = _espace();
    await _ouvrir(tester, espace, theme: themeJarvis(palette));
    final scaffold = tester.widget<Scaffold>(
      find.descendant(
        of: find.byType(ApprendrePage),
        matching: find.byType(Scaffold),
      ),
    );
    expect(scaffold.backgroundColor, palette.ivoirePrincipal);
    final boite = tester.widget<DecoratedBox>(
      find
          .descendant(
            of: find.byKey(const ValueKey('parcours-correspondance')),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    expect(
      (boite.decoration as BoxDecoration).color,
      palette.coque.withValues(alpha: 0.88),
    );
    expect(tester.takeException(), isNull);
    await _fin(tester, espace);
  });
}

class _Lecteur implements LecteurEcoute {
  _Lecteur({required this.reussit});

  final bool reussit;
  final lus = <String>[];

  @override
  bool get disponible => true;

  @override
  Future<bool> lire(String texte) async {
    lus.add(texte);
    return reussit;
  }

  @override
  Future<void> arreter() async {}
}
