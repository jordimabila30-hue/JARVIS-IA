// Captures visuelles de la conversation écrite, avec les vraies polices.
//
//   CAPTURE_DIR=chemin flutter test tool/capture_conversation_test.dart
//
// Rend la vraie page d'accueil (fond, particules, barre) et la pilote comme
// un utilisateur : discussion, conversation collée, choix du ton.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ia_jarvis/pages/accueil_page.dart';
import 'package:ia_jarvis/pages/conversation_page.dart';
import 'package:ia_jarvis/services/conversation/conversation_session.dart';
import 'package:ia_jarvis/theme/theme_jarvis.dart';
import 'package:ia_jarvis/widgets/pim_particle.dart';

import '../test/outils/ecriture.dart';

const _polices = r'C:\flutter\bin\cache\artifacts\material_fonts';

Future<void> _charger(String famille, List<String> fichiers) async {
  final f = FontLoader(famille);
  for (final nom in fichiers) {
    final octets = File(nom).readAsBytesSync();
    f.addFont(Future.value(ByteData.view(octets.buffer)));
  }
  await f.load();
}

const _sarah =
    'Sarah : Tu aurais pu me prévenir.\n'
    'Moi : Désolé, j’étais occupé.\n'
    'Sarah : Ce n’est pas la première fois.';

void main() {
  final dossier = Platform.environment['CAPTURE_DIR'];

  setUpAll(() async {
    await _charger('Roboto', [
      for (final s in ['regular', 'medium', 'bold', 'italic', 'light'])
        '$_polices\\roboto-$s.ttf',
    ]);
    await _charger('MaterialIcons', ['$_polices\\materialicons-regular.otf']);
    await _charger('Exo2', ['assets/polices/Exo2.ttf']);
  });

  const formats = {
    '1920x1080': (Size(1920, 1080), 1.0),
    '1366x768': (Size(1366, 768), 1.0),
    '820x1180': (Size(820, 1180), 1.0),
    '390x844': (Size(390, 844), 2.0),
    '429x599': (Size(429, 599), 2.0),
  };
  final longue = List.generate(
    24,
    (i) => i.isEven
        ? 'Sarah : Message $i, un peu plus long pour voir le retour à la ligne.'
        : 'Moi : Réponse $i.',
  ).join('\n');

  for (final f in formats.entries) {
    testWidgets('conversation ${f.key}', (tester) async {
      final (taille, densite) = f.value;
      tester.view.physicalSize = taille * densite;
      tester.view.devicePixelRatio = densite;
      addTearDown(tester.view.reset);
      final cle = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: cle,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: themeJarvis().copyWith(
              textTheme: themeJarvis().textTheme.apply(fontFamily: 'Roboto'),
            ),
            home: AccueilPage(
              pim: PimController(),
              conversation: ConversationSession(
                delaiReflexion: const Duration(milliseconds: 200),
              ),
            ),
          ),
        ),
      );
      var n = 0;
      Future<void> images(int k) async {
        for (var i = 0; i < k; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
      }

      Future<void> photo(String nom) async {
        n++;
        if (dossier == null) return;
        final objet =
            cle.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await objet.toImage(pixelRatio: densite);
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          File(
            '$dossier/conv_${f.key}_${n.toString().padLeft(2, '0')}_$nom.png',
          ).writeAsBytesSync(png!.buffer.asUint8List());
        });
      }

      Future<void> envoyer(String t) async {
        await tester.enterText(find.byType(EditableText), t);
        await images(5);
        await tester.testTextInput.receiveAction(TextInputAction.send);
        await images(60);
        // Écriture progressive (phase 4) : la réponse, puis ce qui apparaît
        // à la fin (choix du ton…), sont posés avant la photo.
        await finirEcritures(tester);
      }

      final fil = find.byKey(ConversationPage.cleFil);
      ScrollPosition position() => tester
          .state<ScrollableState>(
            find.descendant(of: fil, matching: find.byType(Scrollable)),
          )
          .position;

      await images(60);
      await tester.enterText(find.byType(EditableText), 'Bonjour JARVIS');
      await images(90);
      await photo('frappe');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await images(60);
      await finirEcritures(tester);
      await envoyer('Comment fonctionne une batterie ?');
      await images(60);
      await photo('quelques_messages');
      await envoyer(_sarah);
      await photo('conversation_collee');
      await envoyer('Tu peux me dire quoi répondre ?');
      await photo('choix_du_ton');
      await tester.tap(find.text('Naturel'));
      await images(30);
      await photo('reponse_proposee');
      await envoyer(longue);
      await envoyer('Et là, qu’est-ce que tu en penses ?');
      await images(60);
      await photo('longue_bas');
      position().jumpTo(position().maxScrollExtent / 2);
      await images(10);
      await photo('longue_milieu');
      position().jumpTo(position().maxScrollExtent);
      await images(10);
      await photo('longue_haut');
      position().jumpTo(0);
      await images(10);
      if (taille.width < 600) {
        // Clavier ouvert (téléphone).
        await tester.tap(find.byType(EditableText));
        tester.view.viewInsets = FakeViewPadding(
          bottom: taille.height * 0.4 * densite,
        );
        await images(90);
        await photo('clavier_ouvert');
        tester.view.viewInsets = FakeViewPadding.zero;
        await images(30);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
