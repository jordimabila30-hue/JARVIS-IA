// Captures du bouton vocal de la barre (vraies polices) : sans chat vocal
// ou avec un chat vocal en arrière-plan, champ vide ou avec du texte.
//
//   CAPTURE_DIR=chemin flutter test tool/capture_bouton_vocal_test.dart

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ia_jarvis/theme/theme_jarvis.dart';
import 'package:ia_jarvis/widgets/ligne_de_commande.dart';

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
  });

  testWidgets('bouton vocal : 4 états', (tester) async {
    tester.view.physicalSize = const Size(760, 520) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final cle = GlobalKey();
    Widget barre(bool reprenable, String texte) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: LigneDeCommande(
        controleur: TextEditingController(text: texte),
        focus: FocusNode(),
        onEnvoyer: (_) {},
        onChatVocal: () {},
        chatVocalReprenable: reprenable,
        // Haut-parleur avec le chat vocal en arrière-plan : coupé (champ
        // vide), activé (texte).
        lectureVocale: reprenable ? texte.isNotEmpty : null,
        surLecture: () {},
      ),
    );
    await tester.pumpWidget(
      RepaintBoundary(
        key: cle,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: themeJarvis().copyWith(
            textTheme: themeJarvis().textTheme.apply(fontFamily: 'Roboto'),
          ),
          home: Scaffold(
            backgroundColor: CouleursJarvis.ivoire,
            body: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  barre(false, ''),
                  barre(true, ''),
                  barre(false, 'Bonjour JARVIS'),
                  barre(true, 'Bonjour JARVIS'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    if (dossier == null) return;
    final objet =
        cle.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await objet.toImage(pixelRatio: 2);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      File(
        '$dossier/bouton_vocal.png',
      ).writeAsBytesSync(png!.buffer.asUint8List());
    });
    expect(tester.takeException(), isNull);
  });
}
