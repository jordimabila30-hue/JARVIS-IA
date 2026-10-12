import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ia_jarvis/models/voice_state.dart';
import 'package:ia_jarvis/theme/theme_jarvis.dart';
import 'package:ia_jarvis/widgets/bouton_vocal.dart';
import 'package:ia_jarvis/widgets/ligne_de_commande.dart';

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

  Future<void> afficher(WidgetTester tester, {bool compacte = false}) =>
      tester.pumpWidget(
        MaterialApp(
          theme: themeJarvis(),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: compacte ? 360 : 720,
                child: LigneDeCommande(
                  controleur: controleur,
                  focus: focus,
                  onEnvoyer: envoyes.add,
                  onChatVocal: () => ouvertures++,
                  compacte: compacte,
                ),
              ),
            ),
          ),
        ),
      );

  testWidgets('bouton vocal sans texte, mais avec un libellé accessible', (
    tester,
  ) async {
    final semantique = tester.ensureSemantics();
    await afficher(tester);
    expect(find.text('Chat vocal'), findsNothing);
    expect(find.text(LigneDeCommande.invite), findsOneWidget);
    expect(find.byTooltip('Ouvrir le chat vocal'), findsOneWidget);
    expect(find.bySemanticsLabel('Ouvrir le chat vocal'), findsOneWidget);

    await tester.tap(find.byTooltip('Ouvrir le chat vocal'));
    expect(ouvertures, 1);
    semantique.dispose();
  });

  testWidgets('avec du texte, la capsule envoie le message', (tester) async {
    await afficher(tester);
    await tester.enterText(find.byType(TextField), 'Bonjour JARVIS');
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byTooltip('Envoyer le message'), findsOneWidget);
    await tester.tap(find.byTooltip('Envoyer le message'));
    expect(envoyes, ['Bonjour JARVIS']);
    expect(ouvertures, 0);
  });

  testWidgets('« + » colle une conversation depuis le presse-papiers', (
    tester,
  ) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (appel) async => appel.method == 'Clipboard.getData'
          ? {'text': 'Lui : on se voit demain ?'}
          : null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await afficher(tester);
    await tester.tap(find.byTooltip('Ajouter une conversation'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Coller une conversation'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(controleur.text, 'Lui : on se voit demain ?');
  });

  testWidgets('téléphone : invite courte, aucun débordement', (tester) async {
    await afficher(tester, compacte: true);
    expect(find.text(LigneDeCommande.inviteCourte), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('texte, invite et boutons centrés verticalement', (tester) async {
    for (final compacte in [false, true]) {
      controleur.clear();
      await afficher(tester, compacte: compacte);
      // La capsule anime son changement de hauteur : on attend la fin.
      await tester.pump(const Duration(milliseconds: 400));
      final barre = tester.getRect(find.byType(LigneDeCommande)).center.dy;
      // Le texte est remonté de la correction optique, pas plus.
      final attendu = barre - MesuresBarre.decalageOptique;
      // (La position des lettres de l'invite dépend de la police ; elle a
      // été mesurée au rendu réel : même ligne que le texte saisi.)
      expect(
        tester.getRect(find.byType(EditableText)).center.dy,
        closeTo(attendu, 0.6),
      );
      expect(
        tester.getRect(find.byTooltip('Ajouter une conversation')).center.dy,
        closeTo(barre, 0.5),
      );
      expect(
        tester.getRect(find.byType(BoutonVocal)).center.dy,
        closeTo(barre, 0.5),
      );
      expect(
        tester.getRect(find.byType(LigneDeCommande)).height,
        (compacte ? MesuresBarre.hauteurCompacte : MesuresBarre.hauteur),
      );
      // Avec du texte, la barre se déplie (voir barre_saisie_test.dart) :
      // le texte reste centré sur sa ligne, désormais en haut.
      await tester.enterText(find.byType(TextField), 'Bonjour');
      await tester.pump(const Duration(milliseconds: 400));
      final haut = tester.getRect(find.byType(LigneDeCommande)).top;
      final ligne = compacte
          ? MesuresBarre.hauteurCompacte
          : MesuresBarre.hauteur;
      expect(
        tester.getRect(find.byType(EditableText)).center.dy,
        closeTo(haut + ligne / 2 - MesuresBarre.decalageOptique, 0.6),
      );
      focus.unfocus();
      controleur.clear();
      await tester.pump(const Duration(milliseconds: 400));
    }
  });

  testWidgets('états écoute et parole du bouton vocal', (tester) async {
    for (final etat in [null, VoiceState.listening, VoiceState.speaking]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: BoutonVocal(
              etat: etat,
              libelle: 'Quitter le mode vocal',
              onPressed: () {},
            ),
          ),
        ),
      );
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(tester.takeException(), isNull);
    }
  });
}
