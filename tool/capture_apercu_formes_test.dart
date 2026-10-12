// Captures des formes (vraies polices) : section « Forme principale » des
// Paramètres, puis une démonstration du moteur sur l'accueil.
//
//   CAPTURE_DIR=chemin flutter test tool/capture_apercu_formes_test.dart

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
    '1366x768': (Size(1366, 768), 1.0),
    '390x844': (Size(390, 844), 2.0),
  };

  for (final f in formats.entries) {
    testWidgets('aperçu ${f.key}', (tester) async {
      final (taille, densite) = f.value;
      tester.view.physicalSize = taille * densite;
      tester.view.devicePixelRatio = densite;
      addTearDown(tester.view.reset);
      final cle = GlobalKey();
      final pim = PimController();
      await tester.pumpWidget(
        RepaintBoundary(
          key: cle,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: themeJarvis().copyWith(
              textTheme: themeJarvis().textTheme.apply(fontFamily: 'Roboto'),
            ),
            home: AccueilPage(pim: pim, conversation: ConversationSession()),
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
            '$dossier/apercu_${f.key}_${n.toString().padLeft(2, '0')}_$nom.png',
          ).writeAsBytesSync(png!.buffer.asUint8List());
        });
      }

      await images(40);
      // Paramètres : depuis le menu latéral.
      await tester.tap(find.byTooltip('Menu'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byTooltip('Paramètres'));
      await images(30);
      await tester.tap(find.text('Particules PIM'));
      await images(20);
      // Forme principale : cube (le bloc « Aperçu » n'existe plus).
      await tester.ensureVisible(find.text('Cube 3D').first);
      await tester.tap(find.text('Cube 3D').first);
      await images(10);
      await photo('parametres');
      // Fermeture, puis démonstration d'une autre forme par le moteur.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await images(30);
      pim.lancerApercu(FormePim.tetraedre);
      await images(30);
      await photo('sphere');
      await images(60 * 3);
      await photo('tetraedre');
      await images(60 * 9);
      await photo('retour');
      expect(tester.takeException(), isNull);
    });
  }
}
