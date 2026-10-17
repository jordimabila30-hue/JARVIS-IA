import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ia_jarvis/models/importation/conversation_whatsapp.dart';
import 'package:ia_jarvis/models/importation/filtre_whatsapp.dart';
import 'package:ia_jarvis/pages/filtrage_whatsapp_page.dart';
import 'package:ia_jarvis/services/importation/selection_whatsapp.dart';
import 'package:ia_jarvis/theme/theme_jarvis.dart';
import 'package:ia_jarvis/widgets/importation/apercu_discussion.dart';
import 'package:ia_jarvis/widgets/importation/filtrage/apercu_selection.dart';
import 'package:ia_jarvis/widgets/importation/filtrage/barre_selection.dart';
import 'package:ia_jarvis/widgets/importation/filtrage/commandes_messages.dart';
import 'package:ia_jarvis/widgets/importation/filtrage/commandes_periode.dart';
import 'package:ia_jarvis/widgets/importation/filtrage/selecteur_mode_filtrage.dart';

import 'outils/conversations_whatsapp.dart';

// Mercredi 14 octobre 2026, 10:00.
final _maintenant = DateTime(2026, 10, 14, 10);

ConversationWhatsApp _conversation() => conv([
  msg(0, DateTime(2025, 12, 31, 23, 58), texte: 'avant minuit'),
  msg(1, DateTime(2026, 1, 1, 0, 2), texte: 'après minuit'),
  msg(2, null, texte: 'date illisible'),
  msg(3, DateTime(2026, 9, 30, 12), texte: 'septembre'),
  msg(4, DateTime(2026, 10, 7, 23, 59, 30), texte: 'il y a 7 jours'),
  msg(5, DateTime(2026, 10, 8, 0, 0, 5), texte: 'il y a 6 jours'),
  msg(
    6,
    DateTime(2026, 10, 13, 8),
    type: TypeMessageWhatsApp.systeme,
    texte: 'Alan a rejoint le groupe',
  ),
  msg(7, DateTime(2026, 10, 13, 18), auteur: 'Alan', texte: 'hier'),
  msg(8, DateTime(2026, 10, 14, 9, 15), texte: 'aujourd’hui'),
  msg(9, DateTime(2026, 10, 14, 14, 30, 45), texte: 'cet après-midi'),
]);

Future<void> _images(WidgetTester tester, [int n = 20]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// Capsule de la liste horizontale, amenée à l'écran puis touchée.
Future<void> _capsule(WidgetTester tester, String libelle) async {
  final liste = find.byWidgetPredicate(
    (w) => w is ListView && w.scrollDirection == Axis.horizontal,
  );
  // La rangée elle-même peut avoir défilé hors de la zone des commandes.
  await tester.ensureVisible(liste);
  await _images(tester, 10);
  await tester.dragUntilVisible(
    find.text(libelle),
    liste,
    const Offset(-120, 0),
  );
  await tester.ensureVisible(find.text(libelle));
  await _images(tester, 10);
  await tester.tap(find.text(libelle));
  await _images(tester);
}

/// Amené à l'écran (zone de commandes ou aperçu qui défile), puis touché.
Future<void> _toucher(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await _images(tester, 10);
  // Texte très court d'une bulle : l'heure, posée par-dessus, reçoit le
  // toucher ; la ligne (qui l'englobe) le traite quand même.
  await tester.tap(f, warnIfMissed: false);
}

/// Texte exact d'une bulle (jamais un séparateur de jour).
Finder _bulle(String texte) =>
    find.textContaining(RegExp('^${RegExp.escape(texte)}'));

Future<SelectionWhatsApp> _ouvrir(
  WidgetTester tester, {
  ConversationWhatsApp? conversation,
  SelectionWhatsApp? selection,
  Size taille = const Size(390, 844),
  double police = 1,
  void Function(MessagesChoisisWhatsApp)? surContinuer,
}) async {
  tester.view.physicalSize = taille;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final s =
      selection ??
      SelectionWhatsApp(
        conversation ?? _conversation(),
        horloge: () => _maintenant,
      );
  addTearDown(s.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: themeJarvis(),
      builder: (context, enfant) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(police)),
        child: enfant!,
      ),
      home: FiltrageWhatsAppPage(selection: s, surContinuer: surContinuer),
    ),
  );
  await _images(tester);
  return s;
}

void main() {
  testWidgets('en-tête, deux modes ; par période : aperçu immédiat, '
      'compteur, décocher sans faire disparaître', (tester) async {
    final s = await _ouvrir(tester);
    expect(find.text(FiltrageWhatsAppPage.titre), findsOneWidget);
    expect(find.text('Test · 10 messages'), findsOneWidget);
    expect(find.text(SelecteurModeFiltrage.parPeriode), findsOneWidget);
    expect(find.text(SelecteurModeFiltrage.parMessages), findsOneWidget);
    expect(find.text(BarreSelection.aucun), findsOneWidget);
    expect(find.text(BarreSelection.choisirUn), findsOneWidget);
    // Seules les commandes du mode actif.
    expect(find.text(CommandesMessages.choisirPlage), findsNothing);

    await _capsule(tester, 'Aujourd’hui');
    expect(find.text('2 messages correspondants'), findsOneWidget);
    expect(find.textContaining('aujourd’hui'), findsOneWidget);
    expect(find.textContaining('cet après-midi'), findsOneWidget);
    expect(find.textContaining('hier'), findsNothing);
    expect(find.text('mercredi 14 octobre 2026'), findsOneWidget);
    // Heure réelle (secondes de l'export ignorées à l'affichage).
    expect(find.text('14:30'), findsOneWidget);
    expect(find.text(BarreSelection.compteur(2)), findsOneWidget);

    await tester.tap(find.textContaining('aujourd’hui'));
    await _images(tester);
    expect(find.text(BarreSelection.compteur(1)), findsOneWidget);
    expect(find.textContaining('aujourd’hui'), findsOneWidget);
    final pali = tester.widget<AnimatedOpacity>(
      find.ancestor(
        of: find.textContaining('aujourd’hui'),
        matching: find.byType(AnimatedOpacity),
      ),
    );
    expect(pali.opacity, lessThan(1));
    expect(s.resultat().ids, ['m9']);
    // Un message sans date : signalé, jamais rangé dans une période.
    expect(find.textContaining('sans date reconnue'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('aucun résultat : message clair, bouton inactif', (tester) async {
    final s = SelectionWhatsApp(
      _conversation(),
      horloge: () => DateTime(2027, 2, 2),
    );
    await _ouvrir(tester, selection: s);
    await _capsule(tester, 'Hier');
    expect(find.text(ApercuSelection.aucunMessage), findsOneWidget);
    expect(find.text(BarreSelection.aucun), findsOneWidget);
    final bouton = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text(BarreSelection.continuer),
        matching: find.byType(FilledButton),
      ),
    );
    expect(bouton.onPressed, isNull);
  });

  testWidgets('derniers messages : bornés au nombre réel', (tester) async {
    await _ouvrir(tester);
    await _capsule(tester, 'Derniers messages');
    // 9 messages de participants : 10 dépasserait, seul « Tous (9) » est
    // proposé.
    expect(find.text(CommandesPeriode.tous(9)), findsOneWidget);
    expect(find.text('10'), findsNothing);
    expect(find.text(BarreSelection.compteur(9)), findsOneWidget);
  });

  testWidgets('personnalisé : calendrier (jours mis en évidence, nombre), '
      'navigation mois et année, plage de jours', (tester) async {
    final s = await _ouvrir(tester, taille: const Size(390, 1100));
    await _capsule(tester, 'Personnalisé');
    expect(find.text('Octobre 2026'), findsOneWidget);
    expect(find.text('2 messages le mercredi 14 octobre 2026'), findsOneWidget);
    expect(find.text(BarreSelection.compteur(2)), findsOneWidget);
    // Jour sans message : inactif.
    await _toucher(tester, find.text('10'));
    await _images(tester);
    expect(find.text(BarreSelection.compteur(2)), findsOneWidget);
    // Un jour avec messages.
    await _toucher(tester, find.text('13'));
    await _images(tester);
    expect(find.text('1 message le mardi 13 octobre 2026'), findsOneWidget);
    expect(find.text(PeriodePersonnalisee.toucherSecond), findsOneWidget);
    // Mois précédent, puis un second jour : la période s'étend.
    await _toucher(tester, find.byTooltip('Mois précédent'));
    await _images(tester);
    expect(find.text('Septembre 2026'), findsOneWidget);
    await _toucher(tester, find.text('30'));
    await _images(tester);
    expect(find.text('4 messages dans la période'), findsOneWidget);
    expect(s.resultat().ids, ['m3', 'm4', 'm5', 'm7']);
    // Synchronisé avec Début et Fin.
    expect(find.text('30 septembre 2026'), findsOneWidget);
    expect(find.text('13 octobre 2026'), findsOneWidget);
    // Année : menu.
    await _toucher(tester, find.text('Septembre 2026'));
    await _images(tester);
    await tester.tap(find.text('2025').last);
    await _images(tester, 30);
    expect(find.text('Décembre 2025'), findsOneWidget);
    expect(find.byTooltip('Mois précédent'), findsOneWidget);
    final precedent = tester.widget<IconButton>(
      find.ancestor(
        of: find.byIcon(Icons.chevron_left_rounded),
        matching: find.byType(IconButton),
      ),
    );
    // Premier mois de la conversation : on ne recule plus.
    expect(precedent.onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('heures et minutes au clavier (ordinateur), intervalle '
      'inversé signalé', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      final s = await _ouvrir(tester, taille: const Size(1280, 900));
      await _capsule(tester, 'Personnalisé');
      await tester.tap(find.text('00:00'));
      await _images(tester);
      expect(find.text('Heure de début'), findsOneWidget);
      final champs = find.byType(TextField);
      await tester.enterText(champs.at(0), '09');
      await tester.enterText(champs.at(1), '20');
      await tester.tap(find.text('Valider'));
      await _images(tester);
      expect(s.periode!.debut, DateTime(2026, 10, 14, 9, 20));
      expect(s.resultat().ids, ['m9']);
      // Fin avant le début : signalé, rien ne change.
      await tester.tap(find.text('23:59'));
      await _images(tester);
      await tester.enterText(find.byType(TextField).at(0), '08');
      await tester.enterText(find.byType(TextField).at(1), '00');
      await tester.tap(find.text('Valider'));
      await _images(tester);
      expect(find.text(SelectionWhatsApp.finAvantDebut), findsOneWidget);
      expect(s.resultat().ids, ['m9']);
      // Saisie impossible refusée.
      await tester.tap(find.text('08:00'));
      await _images(tester);
      await tester.enterText(find.byType(TextField).at(0), '27');
      await tester.tap(find.text('Valider'));
      await _images(tester);
      expect(find.textContaining('Heure de 00 à 23'), findsOneWidget);
      await tester.tap(find.text('Annuler'));
      await _images(tester);
      expect(tester.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('heure sur téléphone : roues', (tester) async {
    await _ouvrir(tester);
    await _capsule(tester, 'Personnalisé');
    await tester.tap(find.text('00:00'));
    await _images(tester, 30);
    expect(find.text('Heure de début'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.text('Valider'));
    await _images(tester, 30);
    expect(tester.takeException(), isNull);
  });

  testWidgets('par messages : plage avec indication, cases, date inconnue', (
    tester,
  ) async {
    final s = await _ouvrir(tester, taille: const Size(390, 1500));
    await tester.tap(find.text(SelecteurModeFiltrage.parMessages));
    await _images(tester);
    expect(find.text('Toute la conversation'), findsOneWidget);
    expect(find.text(CommandesMessages.individuel), findsOneWidget);
    // Les commandes de période ne sont plus là.
    expect(find.text('Aujourd’hui'), findsNothing);

    await tester.tap(find.text(CommandesMessages.choisirPlage));
    await _images(tester);
    expect(find.text(CommandesMessages.touchezPremier), findsOneWidget);
    await _toucher(tester, _bulle('septembre'));
    await _images(tester);
    expect(find.text(CommandesMessages.touchezDernier), findsOneWidget);
    await _toucher(tester, _bulle('hier'));
    await _images(tester);
    // L'événement de WhatsApp entre les deux n'est pas un message choisi.
    expect(find.text(BarreSelection.compteur(4)), findsOneWidget);
    expect(find.text(CommandesMessages.individuel), findsOneWidget);
    // La date inconnue : montrée comme telle, cochable à la main.
    expect(find.text(SeparateurJour.dateIllisible), findsOneWidget);
    await _toucher(tester, _bulle('date illisible'));
    await _images(tester);
    expect(find.text(BarreSelection.compteur(5)), findsOneWidget);
    await _toucher(tester, _bulle('hier'));
    await _images(tester);
    expect(s.resultat().ids, ['m2', 'm3', 'm4', 'm5']);
    // L'état survit au changement de mode.
    await tester.tap(find.text(SelecteurModeFiltrage.parPeriode));
    await _images(tester);
    await tester.tap(find.text(SelecteurModeFiltrage.parMessages));
    await _images(tester);
    expect(find.text(BarreSelection.compteur(4)), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('case du côté de la bulle, centrée verticalement sur elle '
      '(multiligne, petit écran)', (tester) async {
    await _ouvrir(
      tester,
      taille: const Size(320, 900),
      conversation: conv([
        msg(0, DateTime(2026, 10, 14, 9), texte: 'à gauche'),
        msg(1, DateTime(2026, 10, 14, 9, 1), auteur: 'Alan', texte: 'à droite'),
        msg(
          2,
          DateTime(2026, 10, 14, 9, 2),
          auteur: 'Alan',
          texte:
              'long à droite\nsur plusieurs\nlignes, assez longues pour '
              'passer à la ligne sur un petit écran',
        ),
        msg(3, DateTime(2026, 10, 14, 9, 3), texte: 'gauche\nencore'),
      ]),
    );
    for (final (texte, droite) in const [
      ('à gauche', false),
      ('à droite', true),
      ('long à droite', true),
      ('gauche', false),
    ]) {
      final ligne = find.ancestor(
        of: _bulle(texte),
        matching: find.byType(LigneCochable),
      );
      final bulle = tester.getRect(
        find
            .descendant(
              of: find.descendant(
                of: ligne,
                matching: find.byType(BulleApercu),
              ),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      final caseR = tester.getRect(
        find.descendant(of: ligne, matching: find.byType(CaseCochee)),
      );
      if (droite) {
        expect(caseR.left, greaterThanOrEqualTo(bulle.right), reason: texte);
      } else {
        expect(caseR.right, lessThanOrEqualTo(bulle.left), reason: texte);
      }
      expect(
        (caseR.center.dy - bulle.center.dy).abs(),
        lessThan(0.5),
        reason: texte,
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('par messages : flèches pour remonter et redescendre '
      'rapidement (3 000 messages, petit écran)', (tester) async {
    final s = await _ouvrir(
      tester,
      taille: const Size(320, 640),
      conversation: reguliere(
        3000,
        DateTime(2025, 1, 1),
        const Duration(minutes: 41),
      ),
    );
    BoutonDefilement fleche(String infobulle) => tester.widget(
      find.ancestor(
        of: find.byTooltip(infobulle),
        matching: find.byType(BoutonDefilement),
      ),
    );
    // Mode « Par période » : aucune flèche.
    expect(find.byType(BoutonDefilement), findsNothing);
    await tester.tap(find.text(SelecteurModeFiltrage.parMessages));
    await _images(tester);
    // Ouvert sur les derniers messages : seule « Monter » est utile.
    expect(fleche(ApercuSelection.monter).visible, isTrue);
    expect(fleche(ApercuSelection.descendre).visible, isFalse);
    expect(_bulle('message 2999'), findsOneWidget);

    await tester.tap(find.byTooltip(ApercuSelection.monter));
    await _images(tester, 120);
    expect(_bulle('message 0'), findsOneWidget);
    expect(fleche(ApercuSelection.monter).visible, isFalse);
    expect(fleche(ApercuSelection.descendre).visible, isTrue);

    await tester.tap(find.byTooltip(ApercuSelection.descendre));
    await _images(tester, 120);
    expect(_bulle('message 2999'), findsOneWidget);
    expect(fleche(ApercuSelection.descendre).visible, isFalse);
    // La sélection n'a pas bougé ; le défilement manuel marche toujours.
    expect(s.nombreSelectionnes, 0);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 400));
    await _images(tester);
    expect(fleche(ApercuSelection.descendre).visible, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('par messages, liste courte : flèches masquées', (tester) async {
    // Assez haut pour que toute la discussion tienne sans défiler.
    await _ouvrir(tester, taille: const Size(390, 1800));
    await tester.tap(find.text(SelecteurModeFiltrage.parMessages));
    await _images(tester);
    for (final b in tester.widgetList<BoutonDefilement>(
      find.byType(BoutonDefilement),
    )) {
      expect(b.visible, isFalse);
    }
  });

  testWidgets('médias groupés : une case pour tous, identifiants gardés', (
    tester,
  ) async {
    final s = await _ouvrir(
      tester,
      conversation: conv([
        for (var i = 0; i < 4; i++)
          msg(
            i,
            DateTime(2026, 10, 1, 9, i),
            type: TypeMessageWhatsApp.media,
            texte: 'IMG-$i.jpg (fichier joint)',
          ),
        msg(4, DateTime(2026, 10, 1, 9, 5), texte: 'voilà'),
      ]),
    );
    await tester.tap(find.text(SelecteurModeFiltrage.parMessages));
    await _images(tester);
    expect(find.text(BulleMediasGroupes.libelle(4)), findsOneWidget);
    await tester.tap(find.text(BulleMediasGroupes.libelle(4)));
    await _images(tester);
    expect(find.text(BarreSelection.compteur(4)), findsOneWidget);
    expect(s.resultat().ids, ['m0', 'm1', 'm2', 'm3']);
    // En partie cochée : case « mixte ».
    s.basculer('m2');
    await _images(tester);
    final c = tester.widget<CaseCochee>(
      find.descendant(
        of: find.ancestor(
          of: find.text(BulleMediasGroupes.libelle(4)),
          matching: find.byType(LigneCochable),
        ),
        matching: find.byType(CaseCochee),
      ),
    );
    expect(c.etat, isNull);
    await tester.tap(find.text(EnteteApercu.toutDecocher));
    await _images(tester);
    expect(find.text(BarreSelection.aucun), findsOneWidget);
  });

  testWidgets('continuer : sans interface 3, inactif et expliqué ; '
      'branché, il reçoit les messages choisis', (tester) async {
    await _ouvrir(tester);
    await _capsule(tester, 'Hier');
    expect(find.text(BarreSelection.indisponible), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.ancestor(
              of: find.text(BarreSelection.continuer),
              matching: find.byType(FilledButton),
            ),
          )
          .onPressed,
      isNull,
    );

    MessagesChoisisWhatsApp? recu;
    await _ouvrir(tester, surContinuer: (m) => recu = m);
    await _capsule(tester, 'Hier');
    await tester.tap(find.text(BarreSelection.continuer));
    await _images(tester);
    expect(recu!.ids, ['m7']);
    expect(recu!.messages.single.auteur, 'Alan');
  });

  testWidgets('20 000 messages : seules les lignes visibles sont '
      'construites', (tester) async {
    final grand = reguliere(
      20000,
      DateTime(2025, 1, 1),
      const Duration(minutes: 17),
    );
    final s = await _ouvrir(tester, conversation: grand);
    expect(find.text('Test · 20 000 messages'), findsOneWidget);
    expect(find.byType(BulleApercu).evaluate().length, lessThan(80));
    await tester.tap(find.text(SelecteurModeFiltrage.parMessages));
    await _images(tester);
    await tester.tap(find.text(EnteteApercu.toutCocher));
    await _images(tester);
    expect(s.nombreSelectionnes, 20000);
    expect(find.text(BarreSelection.compteur(20000)), findsOneWidget);
    expect(find.byType(BulleApercu).evaluate().length, lessThan(80));
    // Défilement dans l'historique.
    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, 3000),
      4000,
    );
    await _images(tester, 60);
    expect(find.byType(BulleApercu).evaluate().length, lessThan(80));
    expect(tester.takeException(), isNull);
  });

  testWidgets('retour (bouton ou Échap) : l’état reste dans la sélection', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final s = SelectionWhatsApp(_conversation(), horloge: () => _maintenant);
    addTearDown(s.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: themeJarvis(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => FiltrageWhatsAppPage(selection: s),
              ),
            ),
            child: const Text('ouvrir'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('ouvrir'));
    await _images(tester, 40);
    await _capsule(tester, 'Hier');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _images(tester, 40);
    expect(find.byType(FiltrageWhatsAppPage), findsNothing);
    await tester.tap(find.text('ouvrir'));
    await _images(tester, 40);
    expect(find.text(BarreSelection.compteur(1)), findsOneWidget);
    await tester.tap(find.byTooltip('Retour'));
    await _images(tester, 40);
    expect(find.byType(FiltrageWhatsAppPage), findsNothing);
  });

  group('mise en page', () {
    for (final (taille, police) in const [
      (Size(320, 568), 1.0),
      (Size(320, 568), 1.6),
      (Size(360, 640), 2.0),
      (Size(390, 844), 1.3),
      (Size(1280, 800), 1.0),
      (Size(1920, 1080), 1.5),
    ]) {
      testWidgets('aucun débordement ($taille, police × $police)', (
        tester,
      ) async {
        await _ouvrir(tester, taille: taille, police: police);
        await _capsule(tester, 'Derniers messages');
        await _capsule(tester, 'Personnalisé');
        await _toucher(tester, find.text('13'));
        await _images(tester);
        expect(tester.takeException(), isNull);
        await _toucher(tester, find.text(SelecteurModeFiltrage.parMessages));
        await _images(tester);
        await _toucher(tester, find.text(CommandesMessages.choisirPlage));
        await _images(tester);
        expect(tester.takeException(), isNull);
        // L'aperçu garde de la place, même sur petit écran.
        expect(
          tester.getSize(find.byType(ApercuSelection)).height,
          greaterThan(taille.height * 0.1),
        );
      });
    }

    testWidgets('ordinateur : commandes à gauche, aperçu à droite', (
      tester,
    ) async {
      await _ouvrir(tester, taille: const Size(1280, 800));
      await _capsule(tester, 'Personnalisé');
      expect(
        tester.getTopLeft(find.byType(ApercuSelection)).dx,
        greaterThan(tester.getTopRight(find.byType(CommandesPeriode)).dx),
      );
    });
  });
}
