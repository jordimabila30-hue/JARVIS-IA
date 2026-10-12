// Captures de la barre de saisie : repos, focus, saisie, multiligne,
// longue conversation collée (vraies polices).
//
//   CAPTURE_DIR=chemin flutter test tool/capture_barre_test.dart

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ia_jarvis/pages/accueil_page.dart';
import 'package:ia_jarvis/services/conversation/conversation_session.dart';
import 'package:ia_jarvis/theme/theme_jarvis.dart';
import 'package:ia_jarvis/widgets/pim_particle.dart';

const _polices = r'C:\flutter\bin\cache\artifacts\material_fonts';

Future<void> _charger(String famille, List<String> fichiers) async {
  final f = FontLoader(famille);
  for (final nom in fichiers) {
    final octets = File(nom).readAsBytesSync();
    f.addFont(Future.value(ByteData.view(octets.buffer)));
  }
  await f.load();
}

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
    '390x844': (Size(390, 844), 2.0),
    '1366x768': (Size(1366, 768), 1.0),
  };

  for (final f in formats.entries) {
    testWidgets('barre ${f.key}', (tester) async {
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
            '$dossier/barre_${f.key}_${n.toString().padLeft(2, '0')}_$nom.png',
          ).writeAsBytesSync(png!.buffer.asUint8List());
        });
      }

      final telephone = taille.width < 600;
      Future<void> clavier(bool ouvert) async {
        if (!telephone) return;
        tester.view.viewInsets = FakeViewPadding(
          bottom: ouvert ? taille.height * 0.4 * densite : 0,
        );
        await images(40);
      }

      // Conversation en cours : particules autour de la barre.
      await images(40);
      await tester.enterText(find.byType(EditableText), 'Bonjour JARVIS');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await images(90);
      FocusManager.instance.primaryFocus?.unfocus();
      await images(90);
      await photo('repos');
      await tester.tap(find.byType(EditableText));
      await clavier(true);
      await images(60);
      await photo('focus');
      await tester.enterText(find.byType(EditableText), 'Salut');
      await images(60);
      await photo('saisie');
      await tester.enterText(
        find.byType(EditableText),
        'Première ligne\nDeuxième ligne\nTroisième ligne',
      );
      await images(60);
      await photo('multiligne');
      await tester.enterText(
        find.byType(EditableText),
        List.generate(20, (i) => 'Sarah : message $i').join('\n'),
      );
      await images(60);
      await photo('longue');
      await tester.enterText(find.byType(EditableText), '');
      FocusManager.instance.primaryFocus?.unfocus();
      await clavier(false);
      await images(60);
      await photo('retour_repos');
      if (telephone) {
        // Longue réponse de JARVIS, puis fermeture du clavier : les
        // particules descendent derrière la carte.
        await tester.tap(find.byType(EditableText));
        await tester.enterText(find.byType(EditableText), 'jdjfbjfjjekej');
        await tester.testTextInput.receiveAction(TextInputAction.send);
        await images(60);
        await tester.tap(find.byType(EditableText));
        await clavier(true);
        await images(90);
        await photo('clavier_ouvert');
        tester.view.viewInsets = FakeViewPadding.zero;
        FocusManager.instance.primaryFocus?.unfocus();
        for (final k in [3, 3, 4]) {
          await images(k);
          await photo('descente');
        }
        await images(90);
        await photo('apres_descente');
      }
      expect(tester.takeException(), isNull);
    });
  }
}
