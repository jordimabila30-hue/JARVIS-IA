// Capture du fond seul (ordinateur et téléphone) pour vérifier qu'une
// nouvelle version du fond reste identique.
//
//   CAPTURE_DIR=chemin flutter test tool/capture_fond_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ia_jarvis/widgets/fond_jarvis_anime.dart';

import 'fond_scene.dart';

void main() {
  final dossier = Platform.environment['CAPTURE_DIR'];
  const formats = {
    'ordi': (Size(1280, 800), 1.5, 520.0),
    'tel': (Size(390, 844), 2.0, 300.0),
    'vocal': (Size(1280, 800), 1.5, 600.0),
  };
  for (final f in formats.entries) {
    testWidgets('fond ${f.key}', (tester) async {
      final (taille, densite, zone) = f.value;
      tester.view.physicalSize = taille * densite;
      tester.view.devicePixelRatio = densite;
      addTearDown(tester.view.reset);
      final cleImage = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: RepaintBoundary(key: cleImage, child: sceneFond(zone)),
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      if (dossier == null) return;
      final objet =
          cleImage.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await objet.toImage(pixelRatio: densite);
        final brut = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        final nom = '$dossier/fond_${f.key}';
        File('$nom.rgba').writeAsBytesSync(brut!.buffer.asUint8List());
        File('$nom.png').writeAsBytesSync(png!.buffer.asUint8List());
        File('$nom.taille').writeAsStringSync('${image.width}x${image.height}');
      });
      // Évite l'avertissement « FondJarvisAnime inutilisé ».
      expect(find.byType(FondJarvisAnime), findsOneWidget);
    });
  }
}
