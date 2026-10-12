// Captures de l'import WhatsApp (vraies polices) : menu « + » (ordinateur)
// et feuille « Ajouter à JARVIS » (téléphone), puis la page d'import : à
// vide, fichier choisi, fichier refusé.
//
//   CAPTURE_DIR=chemin flutter test tool/capture_importation_test.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ia_jarvis/models/importation/export_whatsapp.dart';
import 'package:ia_jarvis/pages/importation_whatsapp_page.dart';
import 'package:ia_jarvis/services/importation/export_local_web.dart'
    as memoire;
import 'package:ia_jarvis/services/importation/identite_whatsapp.dart';
import 'package:ia_jarvis/services/importation/pont_android_importation.dart';
import 'package:ia_jarvis/services/importation/selection_export_whatsapp.dart';
import 'package:ia_jarvis/services/voice_settings_service.dart';
import 'package:ia_jarvis/theme/theme_jarvis.dart';
import 'package:ia_jarvis/widgets/importation/carte_export_choisi.dart';
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

ThemeData _theme() => themeJarvis().copyWith(
  textTheme: Typography.material2021().black
      .merge(themeJarvis().textTheme)
      .apply(fontFamily: 'Roboto'),
);

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
        '$dossier/import_$nom.png',
      ).writeAsBytesSync(png!.buffer.asUint8List());
    });
  }

  for (final (taille, nom, compacte) in const [
    (Size(1366, 768), 'ordinateur', false),
    (Size(390, 844), 'telephone', true),
  ]) {
    testWidgets('menu « + » $nom', (tester) async {
      tester.view.physicalSize = taille * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final controleur = TextEditingController();
      final focus = FocusNode();
      addTearDown(controleur.dispose);
      addTearDown(focus.dispose);
      final cle = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: cle,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: _theme(),
            home: Scaffold(
              body: Align(
                alignment: const Alignment(0, 0.6),
                child: SizedBox(
                  width: compacte ? 358 : 720,
                  child: LigneDeCommande(
                    controleur: controleur,
                    focus: focus,
                    onEnvoyer: (_) {},
                    onChatVocal: () {},
                    compacte: compacte,
                    surImporterWhatsApp: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Ajouter une conversation'));
      // Pas de pumpAndSettle : le curseur du champ clignote sans fin.
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      await photo(tester, cle, 'menu_$nom');
      expect(tester.takeException(), isNull);
    });
  }

  const discussion = """
10/10/2026, 22:41 - Les messages et les appels sont chiffrés de bout en bout.
10/10/2026, 22:41 - Tony Stark: Salut Jordi !
10/10/2026, 22:43 - Jordi: Salut Tony.
10/10/2026, 22:45 - Tony Stark: Tu as terminé le projet ?
10/10/2026, 22:46 - Jordi: Pas encore,
je termine la dernière partie.
11/10/2026, 09:10 - Tony Stark: IMG-20261011-WA0001.jpg (fichier joint)
11/10/2026, 09:10 - Tony Stark: IMG-20261011-WA0002.jpg (fichier joint)
11/10/2026, 09:11 - Tony Stark: VID-20261011-WA0003.mp4 (fichier joint)
11/10/2026, 09:11 - Tony Stark: IMG-20261011-WA0004.jpg (fichier joint)
11/10/2026, 09:12 - Tony Stark: Parfait, tiens-moi au courant.
11/10/2026, 09:14 - Jordi: PTT-20261011-WA0005.opus (fichier joint)
11/10/2026, 09:15 - Jordi: Ok 👍
11/10/2026, 09:15 - Tony Stark: Ce message a été supprimé
""";

  // Page d'import : accueil, lecture en cours, conversation prête,
  // erreur, résumé (téléphone : parcours Android ; ordinateur : sélection).
  for (final (taille, nom, parcours) in const [
    (Size(390, 844), 'telephone', ParcoursImport.partageAndroid),
    (Size(1366, 900), 'ordinateur', ParcoursImport.selection),
  ]) {
    testWidgets('import $nom', (tester) async {
      tester.view.physicalSize = taille * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final cle = GlobalKey();
      Future<void> images([int n = 40]) async {
        for (var i = 0; i < n; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
      }

      Future<void> page(FichierBrut? fichier) async {
        await tester.pumpWidget(
          RepaintBoundary(
            key: cle,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: _theme(),
              home: ImportationWhatsAppPage(
                key: UniqueKey(),
                parcours: parcours,
                partageInitial: fichier == null
                    ? null
                    : PartageRecu(id: 'p', fichiers: [fichier]),
                creerLocal: memoire.creerExportLocal,
                identite: IdentiteWhatsApp(stockage: StockageMemoire()),
              ),
            ),
          ),
        );
        await images(60);
      }

      FichierBrut brut(String n, List<int> o, {int? taille}) => FichierBrut(
        source: SourceReception.partageAndroid,
        nom: n,
        tailleOctets: taille ?? o.length,
        flux: Stream.value(o),
      );

      await page(null);
      await photo(tester, cle, 'page_${nom}_accueil');

      // Lecture en cours : le fichier n'arrive qu'en partie.
      final long = utf8.encode(discussion * 40);
      final flux = StreamController<List<int>>()..add(long.sublist(0, 5000));
      await page(
        FichierBrut(
          source: SourceReception.partageAndroid,
          nom: 'Discussion WhatsApp avec Tony Stark.txt',
          tailleOctets: long.length * 2,
          flux: flux.stream,
        ),
      );
      await photo(tester, cle, 'page_${nom}_lecture');

      await page(
        brut(
          'Discussion WhatsApp avec Tony Stark.txt',
          utf8.encode(discussion),
        ),
      );
      await photo(tester, cle, 'page_${nom}_prete');

      await tester.tap(find.text(CarteExportChoisi.resume));
      await images();
      await photo(tester, cle, 'page_${nom}_resume');

      await page(brut('notes.txt', utf8.encode('Pain\nLait\n')));
      await photo(tester, cle, 'page_${nom}_erreur');
      expect(tester.takeException(), isNull);
      unawaited(flux.close());
    });
  }
}
