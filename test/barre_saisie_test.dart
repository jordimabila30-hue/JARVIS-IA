// Barre de saisie intelligente : repos (compacte), focus et saisie
// (dépliée vers le haut), particules PIM qui suivent la géométrie.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ia_jarvis/pages/accueil_page.dart';
import 'package:ia_jarvis/services/conversation/conversation_session.dart';
import 'package:ia_jarvis/theme/theme_jarvis.dart';
import 'package:ia_jarvis/widgets/bouton_vocal.dart';
import 'package:ia_jarvis/widgets/ligne_de_commande.dart';
import 'package:ia_jarvis/widgets/pim_particle.dart';

const _plus = 'Ajouter une conversation';

double _deplie(bool compacte) {
  final h = compacte ? MesuresBarre.hauteurCompacte : MesuresBarre.hauteur;
  final interieur = h - 2 - 2 * MesuresBarre.marge;
  return h + interieur + MesuresBarre.ecartBoutons;
}

void main() {
  late TextEditingController controleur;
  late FocusNode focus;
  late List<String> envoyes;
  late int ouvertures;

  setUp(() {
    controleur = TextEditingController();
    focus = FocusNode();
    envoyes = [];
    ouvertures = 0;
  });
  tearDown(() {
    controleur.dispose();
    focus.dispose();
  });

  /// Barre posée en bas de l'écran, comme sur l'accueil.
  Future<void> afficher(WidgetTester tester, {bool compacte = false}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: themeJarvis(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 40),
              child: SizedBox(
                width: compacte ? 360 : 720,
                child: LigneDeCommande(
                  controleur: controleur,
                  focus: focus,
                  onEnvoyer: (t) {
                    envoyes.add(t);
                    controleur.clear();
                  },
                  onChatVocal: () => ouvertures++,
                  compacte: compacte,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Rect barre(WidgetTester tester) =>
      tester.getRect(find.byType(LigneDeCommande));

  // Première image : départ des animations ; la seconde les termine.
  Future<void> attendre(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  for (final compacte in [false, true]) {
    final nom = compacte ? 'téléphone' : 'ordinateur';
    final repos = compacte
        ? MesuresBarre.hauteurCompacte
        : MesuresBarre.hauteur;

    testWidgets('$nom : repos → focus → saisie → repos', (tester) async {
      await afficher(tester, compacte: compacte);
      // 1. Repos : une seule ligne, dimensions d'origine.
      final r0 = barre(tester);
      expect(r0.height, repos);
      final plus0 = tester.getRect(find.byTooltip(_plus));
      final vocal0 = tester.getRect(find.byType(BoutonVocal));
      expect(plus0.center.dy, closeTo(r0.center.dy, 0.5));
      expect(
        tester.getRect(find.byType(EditableText)).left,
        greaterThan(plus0.right),
      );

      // 2. Focus sans texte : dépliée vers le haut, bas stable.
      await tester.tap(find.byType(EditableText));
      await attendre(tester);
      expect(focus.hasFocus, isTrue);
      final r1 = barre(tester);
      expect(r1.height, closeTo(_deplie(compacte), 0.5));
      expect(r1.bottom, closeTo(r0.bottom, 0.5));
      // Boutons sur la ligne du bas, à leur place exacte ; champ au-dessus,
      // sur toute la largeur.
      expect(tester.getRect(find.byTooltip(_plus)), plus0);
      expect(tester.getRect(find.byType(BoutonVocal)), vocal0);
      final champ = tester.getRect(find.byType(EditableText));
      expect(champ.bottom, lessThanOrEqualTo(plus0.top));
      expect(champ.left, lessThan(plus0.right));
      expect(champ.right, greaterThan(vocal0.left));
      expect(find.byTooltip('Ouvrir le chat vocal'), findsOneWidget);

      // 3. Un mot : toujours dépliée, bouton d'envoi.
      await tester.enterText(find.byType(EditableText), 'Bonjour');
      await attendre(tester);
      expect(barre(tester).height, closeTo(_deplie(compacte), 0.5));
      expect(find.byTooltip('Envoyer le message'), findsOneWidget);

      // 4. Tout effacer avec le focus : reste dépliée.
      await tester.enterText(find.byType(EditableText), '');
      await attendre(tester);
      expect(barre(tester).height, closeTo(_deplie(compacte), 0.5));

      // 5. Perte du focus avec du texte : reste dépliée.
      await tester.enterText(find.byType(EditableText), 'Brouillon');
      focus.unfocus();
      await attendre(tester);
      expect(barre(tester).height, closeTo(_deplie(compacte), 0.5));
      expect(controleur.text, 'Brouillon');

      // 6. Champ vidé sans focus : retour au repos, comme au début.
      controleur.clear();
      await attendre(tester);
      expect(barre(tester), r0);
      expect(
        tester.getRect(find.byType(EditableText)).left,
        greaterThan(plus0.right),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('$nom : multiligne, 4 lignes puis défilement interne', (
      tester,
    ) async {
      await afficher(tester, compacte: compacte);
      await tester.tap(find.byType(EditableText));
      await attendre(tester);
      final h1 = barre(tester).height;
      await tester.enterText(find.byType(EditableText), 'Un\nDeux\nTrois');
      await attendre(tester);
      final h3 = barre(tester).height;
      expect(h3, greaterThan(h1 + 30));
      // Longue conversation collée : hauteur bornée, texte intact.
      final longue = List.generate(40, (i) => 'Sarah : message $i').join('\n');
      await tester.enterText(find.byType(EditableText), longue);
      await attendre(tester);
      final hMax = barre(tester).height;
      final ligne =
          ((compacte
                      ? MesuresBarre.tailleTexteCompacte
                      : MesuresBarre.tailleTexte) *
                  MesuresBarre.interligne)
              .roundToDouble();
      expect(hMax, closeTo(_deplie(compacte) + 3 * ligne, 1));
      expect(controleur.text, longue);
      // Le texte ne chevauche jamais les boutons.
      final champ = tester.getRect(find.byType(EditableText));
      expect(
        champ.bottom,
        lessThanOrEqualTo(tester.getRect(find.byTooltip(_plus)).top),
      );
      // Défilement interne du champ.
      final defile = tester.state<EditableTextState>(find.byType(EditableText));
      expect(defile.renderEditable.maxScrollExtent, greaterThan(0));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('1 → 4 lignes : la barre grandit, puis reste fixe ; le '
      'curseur suit le texte', (tester) async {
    await afficher(tester, compacte: true);
    await tester.tap(find.byType(EditableText));
    await attendre(tester);
    final hauteurs = <double>[];
    for (var n = 1; n <= 7; n++) {
      await tester.enterText(
        find.byType(EditableText),
        List.generate(n, (i) => 'Ligne ${i + 1}').join('\n'),
      );
      await attendre(tester);
      hauteurs.add(barre(tester).height);
    }
    final ligne = (MesuresBarre.tailleTexteCompacte * MesuresBarre.interligne)
        .roundToDouble();
    for (var n = 1; n < 4; n++) {
      expect(hauteurs[n] - hauteurs[n - 1], closeTo(ligne, 0.5));
    }
    // À partir de 4 lignes, la hauteur ne bouge plus.
    expect(hauteurs[4], hauteurs[3]);
    expect(hauteurs[6], hauteurs[3]);
    // Curseur en fin de texte : le champ a défilé jusqu'à lui.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final etat = tester.state<EditableTextState>(find.byType(EditableText));
    expect(controleur.selection.baseOffset, controleur.text.length);
    expect(
      etat.renderEditable.offset.pixels,
      closeTo(etat.renderEditable.maxScrollExtent, 0.5),
    );
    // Boutons toujours visibles sous le texte.
    expect(
      tester.getRect(find.byType(EditableText)).bottom,
      lessThanOrEqualTo(tester.getRect(find.byTooltip(_plus)).top),
    );
  });

  testWidgets('le champ n’est jamais recréé ni reconstruit pendant le '
      'dépliage (focus, sélection)', (tester) async {
    await afficher(tester);
    await tester.tap(find.byType(EditableText));
    await tester.pump();
    final etat = tester.state(find.byType(EditableText));
    final widget = tester.widget(find.byType(TextField));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(identical(tester.widget(find.byType(TextField)), widget), isTrue);
    }
    await tester.enterText(find.byType(EditableText), 'Bonjour JARVIS');
    controleur.selection = const TextSelection(baseOffset: 0, extentOffset: 7);
    await attendre(tester);
    expect(tester.state(find.byType(EditableText)), same(etat));
    expect(focus.hasFocus, isTrue);
    expect(controleur.selection.textInside(controleur.text), 'Bonjour');
  });

  testWidgets('envoi au bouton : texte envoyé, focus gardé, barre dépliée', (
    tester,
  ) async {
    await afficher(tester);
    await tester.tap(find.byType(EditableText));
    await tester.enterText(find.byType(EditableText), 'Salut');
    await attendre(tester);
    await tester.tap(find.byTooltip('Envoyer le message'));
    await attendre(tester);
    expect(envoyes, ['Salut']);
    expect(focus.hasFocus, isTrue);
    expect(barre(tester).height, closeTo(_deplie(false), 0.5));
    // Entrée (clavier physique) : comportement existant (envoi).
    await tester.enterText(find.byType(EditableText), 'Encore');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await attendre(tester);
    expect(envoyes, ['Salut', 'Encore']);
  });

  testWidgets('« + » et vocal : actions conservées, aux deux états', (
    tester,
  ) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (appel) async => appel.method == 'Clipboard.getData'
          ? <String, dynamic>{'text': 'Lui : on se voit ?'}
          : null,
    );
    await afficher(tester);
    // Repos : vocal.
    await tester.tap(find.byTooltip('Ouvrir le chat vocal'));
    expect(ouvertures, 1);
    // Déplié : « + » ouvre le menu, « Coller » insère et garde le focus.
    await tester.tap(find.byType(EditableText));
    await attendre(tester);
    await tester.tap(find.byTooltip(_plus));
    await attendre(tester);
    expect(focus.hasFocus, isTrue);
    await tester.tap(find.text('Coller une conversation'));
    await attendre(tester);
    expect(controleur.text, 'Lui : on se voit ?');
    expect(focus.hasFocus, isTrue);
    expect(barre(tester).height, closeTo(_deplie(false), 0.5));
    controleur.clear();
    await attendre(tester);
    await tester.tap(find.byTooltip('Ouvrir le chat vocal'));
    expect(ouvertures, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('transition douce : hauteur monotone, sans saut', (tester) async {
    await afficher(tester);
    await tester.tap(find.byType(EditableText));
    var avant = barre(tester).height;
    final bas = barre(tester).bottom;
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final h = barre(tester).height;
      expect(h, greaterThanOrEqualTo(avant - 0.01));
      expect(h - avant, lessThan(14), reason: 'image $i');
      expect(barre(tester).bottom, closeTo(bas, 0.5));
      avant = h;
    }
    expect(avant, closeTo(_deplie(false), 0.5));
    // Repli au repos.
    focus.unfocus();
    for (var i = 0; i < 24; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final h = barre(tester).height;
      expect(h, lessThanOrEqualTo(avant + 0.01));
      avant = h;
    }
    expect(avant, MesuresBarre.hauteur);
  });

  group('Sur la page d’accueil', () {
    Future<PimController> page(WidgetTester tester, Size taille) async {
      tester.view.physicalSize = taille;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final pim = PimController();
      await tester.pumpWidget(
        MaterialApp(
          theme: themeJarvis(),
          home: AccueilPage(
            pim: pim,
            conversation: ConversationSession(
              delaiReflexion: const Duration(milliseconds: 200),
            ),
          ),
        ),
      );
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      return pim;
    }

    Future<void> images(WidgetTester tester, int n) async {
      for (var i = 0; i < n; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    /// Ligne la plus haute dessinée par les particules (écran).
    Future<double> hautPim(WidgetTester tester) async {
      final objet = tester.renderObject<RenderRepaintBoundary>(
        find
            .descendant(
              of: find.byType(PimParticle),
              matching: find.byType(RepaintBoundary),
            )
            .first,
      );
      var haut = double.infinity;
      await tester.runAsync(() async {
        final image = await objet.toImage();
        final o = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
        for (var y = 0; y < image.height && haut.isInfinite; y++) {
          for (var x = 0; x < image.width; x++) {
            if (o.getUint8((y * image.width + x) * 4 + 3) > 12) {
              haut = y.toDouble();
              break;
            }
          }
        }
      });
      return haut + tester.getTopLeft(find.byType(PimParticle)).dy;
    }

    testWidgets('téléphone : clavier, dépliage, fermeture avec et sans '
        'texte', (tester) async {
      const ecran = Size(390, 844);
      await page(tester, ecran);
      final repos = barre(tester);
      await tester.tap(find.byType(EditableText));
      const clavier = 330.0;
      for (var i = 1; i <= 15; i++) {
        tester.view.viewInsets = FakeViewPadding(bottom: clavier * i / 15);
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.takeException(), isNull);
      }
      await images(tester, 30);
      final ouverte = barre(tester);
      expect(ouverte.height, closeTo(_deplie(true), 0.5));
      expect(ouverte.bottom, lessThanOrEqualTo(ecran.height - clavier));
      // Longue conversation collée, clavier ouvert : aucun débordement.
      await tester.enterText(
        find.byType(EditableText),
        List.generate(30, (i) => 'Sarah : message $i').join('\n'),
      );
      await images(tester, 30);
      expect(tester.takeException(), isNull);
      expect(barre(tester).top, greaterThan(0));
      // Clavier fermé (le focus reste) avec du texte : toujours dépliée.
      tester.view.viewInsets = FakeViewPadding.zero;
      await images(tester, 30);
      expect(barre(tester).height, greaterThan(_deplie(true)));
      // Champ vidé puis focus perdu : retour au repos d'origine.
      await tester.enterText(find.byType(EditableText), '');
      FocusManager.instance.primaryFocus?.unfocus();
      await images(tester, 40);
      expect(barre(tester), repos);
      expect(tester.takeException(), isNull);
    });

    testWidgets('envoi : message dans le fil, champ vidé, barre dépliée '
        'tant que le focus reste', (tester) async {
      await page(tester, const Size(1366, 768));
      await tester.tap(find.byType(EditableText));
      await tester.enterText(find.byType(EditableText), 'Bonjour JARVIS');
      await images(tester, 20);
      await tester.tap(find.byTooltip('Envoyer le message'));
      await images(tester, 40);
      expect(find.text('Bonjour JARVIS'), findsOneWidget);
      final champ = tester.widget<EditableText>(find.byType(EditableText));
      expect(champ.controller.text, isEmpty);
      expect(champ.focusNode.hasFocus, isTrue);
      expect(barre(tester).height, closeTo(_deplie(false), 0.5));
      expect(tester.takeException(), isNull);
    });

    testWidgets('mode vocal depuis la barre dépliée', (tester) async {
      await page(tester, const Size(1366, 768));
      await tester.tap(find.byType(EditableText));
      await images(tester, 20);
      await tester.tap(find.byTooltip('Ouvrir le chat vocal'));
      await images(tester, 60);
      expect(find.text('Quitter le mode vocal'), findsOneWidget);
      await tester.tap(find.text('Quitter le mode vocal'));
      await images(tester, 60);
      // Retour : focus rendu au système, barre au repos.
      expect(barre(tester).height, MesuresBarre.hauteur);
      expect(tester.takeException(), isNull);
    });

    testWidgets('PIM suit la barre qui se déplie puis se replie', (
      tester,
    ) async {
      final pim = await page(tester, const Size(1366, 768));
      // Conversation : les particules entourent la barre.
      await tester.enterText(find.byType(EditableText), 'Bonjour JARVIS');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await images(tester, 150);
      expect(FocusManager.instance.primaryFocus?.hasPrimaryFocus, isTrue);
      FocusManager.instance.primaryFocus?.unfocus();
      await images(tester, 90);
      final r0 = barre(tester);
      final haut0 = await hautPim(tester);
      expect(r0.top - haut0, inInclusiveRange(15, 50));

      await tester.tap(find.byType(EditableText));
      await images(tester, 90);
      final r1 = barre(tester);
      final haut1 = await hautPim(tester);
      expect(r1.height, closeTo(_deplie(false), 0.5));
      // Le contour a suivi la nouvelle géométrie (même écart à la barre).
      expect(r1.top - haut1, closeTo(r0.top - haut0, 12));
      expect(pim.mode, isNot(ParticlePimMode.movingToCenter));

      FocusManager.instance.primaryFocus?.unfocus();
      await images(tester, 90);
      expect(barre(tester), r0);
      expect(
        barre(tester).top - await hautPim(tester),
        closeTo(r0.top - haut0, 12),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('fenêtre redimensionnée, barre dépliée avec texte', (
      tester,
    ) async {
      await page(tester, const Size(1366, 768));
      await tester.tap(find.byType(EditableText));
      await tester.enterText(find.byType(EditableText), 'Un\nDeux\nTrois');
      await images(tester, 20);
      for (final s in const [
        Size(1920, 1080),
        Size(820, 1180),
        Size(429, 599),
        Size(390, 844),
        Size(1100, 700),
      ]) {
        tester.view.physicalSize = s;
        await images(tester, 30);
        expect(tester.takeException(), isNull, reason: '$s');
        final r = barre(tester);
        expect(r.top, greaterThan(0), reason: '$s');
        expect(r.bottom, lessThanOrEqualTo(s.height), reason: '$s');
        expect(
          tester
              .widget<EditableText>(find.byType(EditableText))
              .controller
              .text,
          'Un\nDeux\nTrois',
        );
      }
    });
  });
}
