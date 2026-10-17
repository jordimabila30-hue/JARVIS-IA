// Captures de l'interface 2 de l'import WhatsApp, « Filtrer les messages »
// (vraies polices) : téléphone (période, personnalisé avec calendrier, par
// messages avec plage) et ordinateur.
//
//   CAPTURE_DIR=chemin flutter test tool/capture_filtrage_test.dart

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ia_jarvis/pages/filtrage_whatsapp_page.dart';
import 'package:ia_jarvis/services/importation/analyseur_whatsapp.dart';
import 'package:ia_jarvis/services/importation/selection_whatsapp.dart';
import 'package:ia_jarvis/theme/theme_jarvis.dart';
import 'package:ia_jarvis/widgets/importation/filtrage/commandes_messages.dart';
import 'package:ia_jarvis/widgets/importation/filtrage/selecteur_mode_filtrage.dart';

const _polices = r'C:\flutter\bin\cache\artifacts\material_fonts';

Future<void> _charger(String famille, List<String> fichiers) async {
  final f = FontLoader(famille);
  for (final nom in fichiers) {
    final octets = File(nom).readAsBytesSync();
    f.addFont(Future.value(ByteData.view(octets.buffer)));
  }
  await f.load();
}

ThemeData _theme() => themeJarvis().copyWith(
  textTheme: Typography.material2021().black
      .merge(themeJarvis().textTheme)
      .apply(fontFamily: 'Roboto'),
);

const _export = '''
11/10/2026, 14:30 - Les messages et les appels sont chiffrés de bout en bout.
28/09/2026, 18:02 - Tony Stark: On se voit samedi pour le prototype ?
28/09/2026, 18:05 - Pepper: Oui, 10 h à l'atelier.
03/10/2026, 10:12 - Tony Stark: Je suis là.
03/10/2026, 10:40 - Pepper: <Médias omis>
03/10/2026, 10:40 - Pepper: <Médias omis>
03/10/2026, 10:41 - Pepper: <Médias omis>
03/10/2026, 10:41 - Pepper: <Médias omis>
08/10/2026, 21:15 - Tony Stark: Les tests de l'armure sont concluants.
Il reste à régler la stabilisation.
08/10/2026, 21:17 - Pepper: Super, tiens-moi au courant.
13/10/2026, 08:03 - Tony Stark: Réunion déplacée à 15 h.
13/10/2026, 08:10 - Pepper: Noté.
13/10/2026, 19:44 - Tony Stark: Tu as reçu le rapport ?
14/10/2026, 09:15 - Pepper: Oui, je le lis ce matin.
14/10/2026, 09:16 - Tony Stark: Merci !
''';

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

  SelectionWhatsApp selection() {
    final a = AnalyseurWhatsApp();
    for (final l in const LineSplitter().convert(_export)) {
      a.ajouterLigne(l);
    }
    final c = a.terminer(nomFichier: 'Discussion WhatsApp avec Pepper.txt');
    return SelectionWhatsApp(c, horloge: () => DateTime(2026, 10, 14, 10));
  }

  Future<void> images(WidgetTester tester, [int n = 30]) async {
    for (var i = 0; i < n; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  Future<void> photo(WidgetTester tester, GlobalKey cle, String nom) async {
    if (dossier == null) return;
    final objet =
        cle.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      // Laisse flutter_svg décoder le logo.
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    await tester.runAsync(() async {
      final image = await objet.toImage(pixelRatio: 1);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      File(
        '$dossier/filtrage_$nom.png',
      ).writeAsBytesSync(png!.buffer.asUint8List());
    });
  }

  Future<GlobalKey> afficher(
    WidgetTester tester,
    Size taille,
    SelectionWhatsApp s,
  ) async {
    tester.view.physicalSize = taille * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final cle = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: cle,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: _theme(),
          home: FiltrageWhatsAppPage(selection: s),
        ),
      ),
    );
    await images(tester);
    return cle;
  }

  testWidgets('téléphone', (tester) async {
    final s = selection();
    final cle = await afficher(tester, const Size(390, 844), s);
    await photo(tester, cle, 'telephone_depart');
    s.choisirCapsule(CapsulePeriode.septJours);
    s.basculer('m10');
    await images(tester);
    await photo(tester, cle, 'telephone_7jours');
    s.choisirCapsule(CapsulePeriode.personnalise);
    s.choisirJour(DateTime(2026, 10, 8));
    s.choisirJour(DateTime(2026, 10, 13));
    await images(tester);
    await photo(tester, cle, 'telephone_personnalise');
    await tester.tap(find.text(SelecteurModeFiltrage.parMessages));
    await images(tester);
    await tester.tap(find.text(CommandesMessages.choisirPlage));
    await images(tester);
    s.designer('m3');
    await images(tester);
    await photo(tester, cle, 'telephone_plage');
    expect(tester.takeException(), isNull);
  });

  testWidgets('ordinateur', (tester) async {
    final s = selection();
    final cle = await afficher(tester, const Size(1366, 768), s);
    s.choisirCapsule(CapsulePeriode.personnalise);
    s.modifierDebut(DateTime(2026, 10, 13, 8, 5));
    await images(tester);
    await photo(tester, cle, 'ordinateur_personnalise');
    expect(tester.takeException(), isNull);
  });
}
